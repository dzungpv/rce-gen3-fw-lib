-------------------------------------------------------------------------------
-- Title         : PPI To VC Block, Outbound Transmit.
-- File          : PpiVcOb.vhd
-- Author        : Ryan Herbst, rherbst@slac.stanford.edu
-- Created       : 03/21/2014
-------------------------------------------------------------------------------
-- Description:
-- PPI block to transmit outbound VC Frames.
-- First word of PPI frame contains control data:
--    Bits 03:00 = VC
--    Bits 8     = SOF
--    Bits 9     = EOF
--    Bits 10    = EOFE
--    Bits 63:11 = Ignored
-------------------------------------------------------------------------------
-- Copyright (c) 2014 by Ryan Herbst. All rights reserved.
-------------------------------------------------------------------------------
-- Modification history:
-- 03/21/2014: created.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

use work.ArmRceG3Pkg.all;
use work.StdRtlPkg.all;
use work.Vc64Pkg.all;

entity PpiVcOb is
   generic (
      TPD_G              : time := 1 ns;
      VC_WIDTH_G         : integer range 16 to 64     := 16;  -- 16, 32 or 64
      VC_COUNT_G         : integer range 1  to 16     := 4;   -- Number of VCs
      PPI_ADDR_WIDTH_G   : integer range 2 to 48      := 9;   -- (2**9) * 64 bits = 4096 bytes
      PPI_PAUSE_THOLD_G  : integer range 2 to (2**24) := 256; -- 256 * 64 bits = 2048 bytes
      PPI_READY_THOLD_G  : integer range 0 to 511     := 0    -- 0 * 64 bits = 0 bytes
   );
   port (

      -- PPI Interface
      ppiClk           : in  sl;
      ppiClkRst        : in  sl;
      ppiOnline        : in  sl;
      ppiWriteToFifo   : in  PpiWriteToFifoType;
      ppiWriteFromFifo : out PpiWriteFromFifoType;

      -- Outbound VC Interface, ready is used for handshake
      obVcClk          : in  sl;
      obVcClkRst       : in  sl;
      obVcData         : out Vc64DataType;
      obVcCtrl         : in  Vc64CtrlArray(VC_COUNT_G-1 downto 0);

      -- Frame Counter
      remOverflow      : out sl;
      txFrameCntEn     : out sl
   );

begin
   assert (VC_WIDTH_G = 16 or VC_WIDTH_G = 32 or VC_WIDTH_G = 64 ) 
      report "VC_WIDTH_G must not be = 16, 32 or 64" severity failure;
end PpiVcOb;

architecture structure of PpiVcOb is

   -- Local signals
   signal intReadToFifo    : PpiReadToFifoType;
   signal intReadFromFifo  : PpiReadFromFifoType;
   signal intOnline        : sl;
   signal intVcCtrl        : Vc64CtrlArray(15 downto 0);

   type StateType is (S_IDLE_C, S_FIRST_C, S_DATA_C, S_LAST_C);

   type RegType is record
      state          : StateType;
      pos            : slv(1 downto 0);
      vc             : slv(3 downto 0);
      sof            : sl;
      eof            : sl;
      eofe           : sl;
      txFrameCntEn   : sl;
      ppiReadToFifo  : PpiReadToFifoType;
      obVcData       : Vc64DataType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state          => S_IDLE_C,
      pos            => (others=>'0'),
      vc             => (others=>'0'),
      sof            => '0',
      eof            => '0',
      eofe           => '0',
      txFrameCntEn   => '0',
      ppiReadToFifo  => PPI_READ_TO_FIFO_INIT_C,
      obVcData       => VC64_DATA_INIT_C
   );

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

   ------------------------------------
   -- Connect VC control
   ------------------------------------
   process (obVcCtrl) begin
      intVcCtrl                        <= (others=>VC64_CTRL_FORCE_C);
      intVcCtrl(VC_COUNT_G-1 downto 0) <= obVcCtrl;

      remOverflow <= '0';

      for i in 0 to VC_COUNT_G-1 loop
         if obVcCtrl(i).overflow = '1' then
            remOverflow <= '1';
         end if;
      end loop;

   end process;


   ------------------------------------
   -- FIFO
   ------------------------------------

   U_InFifo : entity work.PpiFifo
      generic map (
         TPD_G              => TPD_G,
         ADDR_WIDTH_G       => PPI_ADDR_WIDTH_G,
         PAUSE_THOLD_G      => PPI_PAUSE_THOLD_G,
         READY_THOLD_G      => PPI_READY_THOLD_G
      ) port map (
         ppiWrClk         => ppiClk,
         ppiWrClkRst      => ppiClkRst,
         ppiWrOnline      => ppiOnline,
         ppiWriteToFifo   => ppiWriteToFifo,
         ppiWriteFromFifo => ppiWriteFromFifo,
         ppiRdClk         => obVcClk,
         ppiRdClkRst      => obVcClkRst,
         ppiRdOnline      => intOnline,
         ppiReadToFifo    => intReadToFifo,
         ppiReadFromFifo  => intReadFromFifo
      );


   ------------------------------------
   -- Data Mover
   ------------------------------------

   -- Sync
   process (obVcClk) is
   begin
      if (rising_edge(obVcClk)) then
         r <= rin after TPD_G;
      end if;
   end process;

   -- Async
   process (obVcClkRst, r, intReadFromFifo, intVcCtrl, intOnline ) is
      variable v         : RegType;
      variable nextData  : slv(63 downto 0);
      variable nextEof   : sl;
      variable nextSize  : sl;
      variable nextPos   : slv(1 downto 0);
      variable nextRead  : sl;
   begin
      v := r;

      -- Init
      v.ppiReadToFifo.read := '0';
      v.txFrameCntEn       := '0';

      -- Init valid signal
      v.obVcData.valid := '0';

      -- Determine data alignment and EOF
      nextData := (others=>'0');
      nextEof  := '0';
      nextPos  := "00";
      nextRead := '0';
      nextSize := '0';

      case VC_WIDTH_G is

         -- 16 bit VC
         when 16 =>
            case r.pos is
               when "00" =>
                  nextData := x"000000000000" & intReadFromFifo.data(15 downto 0); -- 0/1
                  nextEof  := ite(intReadFromFifo.eof = '1' and intReadFromFifo.size <= 1,'1','0');
                  nextRead := nextEof;
                  nextPos  := "01";
               when "01" =>
                  nextData := x"000000000000" & intReadFromFifo.data(31 downto 16); -- 2/3
                  nextEof  := ite(intReadFromFifo.eof = '1' and intReadFromFifo.size <= 3,'1','0');
                  nextRead := nextEof;
                  nextPos  := "10";
               when "10" =>
                  nextData := x"000000000000" & intReadFromFifo.data(47 downto 32); -- 4/5
                  nextEof  := ite(intReadFromFifo.eof = '1' and intReadFromFifo.size <= 5,'1','0');
                  nextRead := nextEof;
                  nextPos  := "11";
               when "11" =>
                  nextData := x"000000000000" & intReadFromFifo.data(63 downto 48); -- 6/7
                  nextEof  := intReadFromFifo.eof;
                  nextRead := '1';
                  nextPos  := "00";
               when others => null;
            end case;

         -- 32 bit VC
         when 32 =>
            case r.pos is
               when "00" =>
                  nextData := x"00000000" & intReadFromFifo.data(31 downto 0); -- 0/1/2/3
                  nextEof  := ite(intReadFromFifo.eof = '1' and intReadFromFifo.size <= 3,'1','0');
                  nextRead := nextEof;
                  nextPos  := "10";
               when "10" =>
                  nextData := x"00000000" & intReadFromFifo.data(63 downto 32); -- 4/5/6/7
                  nextEof  := intReadFromFifo.eof;
                  nextRead := '1';
                  nextPos  := "00";
               when others => null;
            end case;

         -- 64 bit VC
         when 64 =>
            nextData := intReadFromFifo.data;
            nextEof  := intReadFromFifo.eof;
            nextSize := intReadFromFifo.size(0);
            nextRead := '1';
         when others => null;
      end case;

      -- State Machine
      case r.state is

         -- Idle
         when S_IDLE_C =>
            if intReadFromFifo.valid = '1' and intReadFromFifo.ready = '1' then
               v.vc                 := intReadFromFifo.data(3 downto 0);
               v.sof                := intReadFromFifo.data(8);
               v.eof                := intReadFromFifo.data(9);
               v.eofe               := intReadFromFifo.data(10);
               v.ppiReadToFifo.read := '1';
               v.pos                := "00";

               -- Not Bad frame, otherwise skip
               if intReadFromFifo.eof /= '1' then
                  v.state := S_FIRST_C;
               end if;
            end if;

         -- First, put data onto interface
         when S_FIRST_C =>
            v.obVcData.sof       := r.sof;
            v.obVcData.data      := nextData;
            v.obVcData.valid     := (not intVcCtrl(conv_integer(r.vc)).almostFull);
            v.obVcData.vc        := r.vc;
            v.obVcData.size      := nextSize;
            v.ppireadToFifo.read := nextRead;
            v.pos                := nextPos;

            if nextEof = '1' then
               v.obVcData.eof  := r.eof;
               v.obVcData.eofe := r.eofe;
               v.state         := S_LAST_C;
            else
               v.obVcData.eof  := '0';
               v.obVcData.eofe := '0';
               v.state         := S_DATA_C;
            end if;

         -- Normal Data
         when S_DATA_C =>
            v.obVcData.valid := (not intVcCtrl(conv_integer(r.vc)).almostFull);

            if intVcCtrl(conv_integer(r.vc)).ready = '1' and r.obVcData.valid = '1' then
               v.obVcData.sof       := '0';
               v.obVcData.data      := nextData;
               v.ppireadToFifo.read := nextRead;
               v.pos                := nextPos;

               if nextEof = '1' then
                  v.obVcData.eof  := r.eof;
                  v.obVcData.eofe := r.eofe;
                  v.state         := S_LAST_C;
               end if;
            end if;

         -- Last Transfer
         when S_LAST_C =>
            v.obVcData.valid := (not intVcCtrl(conv_integer(r.vc)).almostFull);

            if intVcCtrl(conv_integer(r.vc)).ready = '1' and r.obVcData.valid = '1' then
               v.txFrameCntEn   := r.obVcData.eof;
               v.obVcData.valid := '0';
               v.state          := S_IDLE_C;
            end if;

         when others =>
            v.state := S_IDLE_C;

      end case;

      -- Reset
      if obVcClkRst = '1' or intOnline = '0' then
         v := REG_INIT_C;
      end if;

      -- Next register assignment
      rin <= v;

      -- Outputs
      intReadToFifo <= v.ppiReadToFifo;
      obVcData      <= r.obVcData;
      txFrameCntEn  <= r.txFrameCntEn;

   end process;

end architecture structure;

