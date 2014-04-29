-------------------------------------------------------------------------------
-- Title         : ARM Based RCE Generation 3, Outbound Header FIFOs
-- File          : ArmRceG3ObHeaderFifo.vhd
-- Author        : Ryan Herbst, rherbst@slac.stanford.edu
-- Created       : 07/09/2013
-------------------------------------------------------------------------------
-- Description:
-- Outbound header FIFO for PPI DMA Engines.
-- Header size is 256 bytes 
-- 1 cache line read = 4 x 8 = 32 bytes
-- Max burst will be 8 read requests (32 outbound FIFO locations)
-------------------------------------------------------------------------------
-- Copyright (c) 2013 by Ryan Herbst. All rights reserved.
-------------------------------------------------------------------------------
-- Modification history:
-- 07/09/2013: created.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use ieee.std_logic_arith.all;
use IEEE.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

use work.ArmRceG3Pkg.all;
use work.StdRtlPkg.all;
use work.AxiPkg.all;

entity ArmRceG3ObHeaderFifo is
   generic (
      TPD_G        : time          := 1 ns;
      PPI_CONFIG_G : PpiConfigType := PPI_CONFIG_INIT_C
   );
   port (

      -- Clock & reset
      axiClk                  : in  sl;
      axiClkRst               : in  sl;

      -- AXI Read Interface
      axiReadToCntrl          : out AxiReadToCntrlType;
      axiReadFromCntrl        : in  AxiReadFromCntrlType;

      -- Transmit Descriptor write
      headerPtrWrite          : in  sl;
      headerPtrData           : in  slv(35 downto 0);

      -- Free list FIFO (finished descriptors)
      freePtrWrite            : out sl;
      freePtrData             : out slv(17 downto 0);

      -- Configuration
      memBaseAddress          : in  slv(31 downto 18);
      fifoEnable              : in  sl;
      headerReadDmaId         : in  slv(2 downto 0);

      -- FIFO Interface
      obHeaderToFifo          : in  ObHeaderToFifoType;
      obHeaderFromFifo        : out ObHeaderFromFifoType
   );
end ArmRceG3ObHeaderFifo;

architecture structure of ArmRceG3ObHeaderFifo is

   -- FIFO is program full when less than 40 locations are available
   -- Max header size is 256 bytes (32 locations)
   constant OB_HEADER_FULL_THRESH_C : integer := (2**PPI_CONFIG_G.obHeaderAddrWidth) - 40;

   -- Outbound descriptor
   type ObDescType is record
      offset   : slv(17 downto 0);
      length   : slv(7 downto 0);
      htype    : slv(3 downto 0);
      code     : slv(1 downto 0);
      valid    : sl;
   end record;

   -- States
   type States is ( ST_IDLE, ST_REQ, ST_READ, ST_CHECK, ST_WAIT, ST_FREE );

   -- Local signals
   signal obDesc                   : ObDescType;
   signal headerPtrDout            : slv(35 downto 0);
   signal nextFreeWrite            : sl;
   signal headerDin                : slv(71 downto 0);
   signal headerDout               : slv(71 downto 0);
   signal header                   : ObHeaderFromFifoType;
   signal rxLengthCnt              : slv(7  downto 0);
   signal rxDone                   : sl;
   signal rxLast                   : sl;
   signal rxInit                   : sl;
   signal obHeaderPFull            : sl;
   signal addrValid                : sl;
   signal readAddr                 : slv(31 downto 0);
   signal readPending              : slv(7  downto 0);
   signal nextReq                  : sl;
   signal fifoReq                  : sl;
   signal curState                 : States;
   signal nxtState                 : States;
   signal dbgState                 : slv(2 downto 0);
   signal axiClkRstInt             : sl := '1';

   attribute mark_debug : string;
   attribute mark_debug of axiClkRstInt : signal is "true";

   attribute INIT : string;
   attribute INIT of axiClkRstInt : signal is "1";

begin

   -- Reset registration
   process ( axiClk ) begin
      if rising_edge(axiClk) then
         axiClkRstInt <= axiClkRst after TPD_G;
      end if;
   end process;

   -- State Debug
   dbgState <= conv_std_logic_vector(States'POS(curState), 3);

   -----------------------------------------
   -- Transmit Descriptor FIFO
   -----------------------------------------
   U_TxFifo : entity work.Fifo
      generic map (
         TPD_G           => TPD_G,
         RST_POLARITY_G  => '1',
         RST_ASYNC_G     => false,
         GEN_SYNC_FIFO_G => true,
         BRAM_EN_G       => true,
         FWFT_EN_G       => true,
         USE_DSP48_G     => "no",
         USE_BUILT_IN_G  => true,
         XIL_DEVICE_G    => "7SERIES",
         SYNC_STAGES_G   => 3,
         DATA_WIDTH_G    => 36,
         ADDR_WIDTH_G    => 9,
         INIT_G          => "0",
         FULL_THRES_G    => 1,
         EMPTY_THRES_G   => 1
      ) port map (
         rst                => axiClkRstInt,
         wr_clk             => axiClk,
         wr_en              => headerPtrWrite,
         din                => headerPtrData,
         wr_data_count      => open,
         wr_ack             => open,
         overflow           => open,
         prog_full          => open,
         almost_full        => open,
         full               => open,
         not_full           => open,
         rd_clk             => axiClk,
         rd_en              => nextFreeWrite,
         dout               => headerPtrDout,
         rd_data_count      => open,
         valid              => obDesc.valid,
         underflow          => open,
         prog_empty         => open,
         almost_empty       => open,
         empty              => open
      );

   -- Connect output
   obDesc.code     <= headerPtrDout(31 downto 30);
   obDesc.htype    <= headerPtrDout(29 downto 26);
   obDesc.length   <= headerPtrDout(25 downto 18);
   obDesc.offset   <= headerPtrDout(17 downto  0);

   -----------------------------------------
   -- State machine
   -----------------------------------------

   -- AXI read master
   axiReadToCntrl.req       <= fifoReq;
   axiReadToCntrl.address   <= readAddr(31 downto 3);
   axiReadToCntrl.avalid    <= addrValid;
   axiReadToCntrl.id        <= headerReadDmaId;
   axiReadToCntrl.length    <= "0011";
   axiReadToCntrl.afull     <= '0';

   -- Sync states
   process ( axiClk ) begin
      if rising_edge(axiClk) then
         if axiClkRstInt = '1' then
            curState        <= ST_IDLE          after TPD_G;
            freePtrWrite    <= '0'              after TPD_G;
            freePtrData     <= (others=>'0')    after TPD_G;
            readAddr        <= (others=>'0')    after TPD_G;
            readPending     <= (others=>'0')    after TPD_G;
            fifoReq         <= '0'              after TPD_G;
         else

            -- State
            curState <= nxtState after TPD_G;
            fifoReq  <= nextReq  after TPD_G;

            -- Free list write
            freePtrData  <= obDesc.offset after TPD_G;
            freePtrWrite <= nextFreeWrite after TPD_G;

            -- Reset counters
            if rxInit = '1' then
               readAddr    <= memBaseAddress & obDesc.offset after TPD_G;
               readPending <= (others=>'0')                  after TPD_G;

            -- Increment pending and address
            elsif addrValid = '1' then
               readAddr    <= readAddr    + 32 after TPD_G;
               readPending <= readPending + 4  after TPD_G;
            end if;
         end if;
      end if;
   end process;

   -- ASync states
   process ( curState, obDesc, rxDone, rxLast, fifoEnable, 
             axiReadFromCntrl, obHeaderPFull, readPending, rxLengthCnt ) begin

      -- Init signals
      nxtState        <= curState;
      nextFreeWrite   <= '0';
      addrValid       <= '0';
      rxInit          <= '0';
      nextReq         <= '0';

      -- State machine
      case curState is 

         -- Idle
         when ST_IDLE =>
            rxInit <= '1';

            -- Fifo has data
            if obDesc.valid = '1' and fifoEnable = '1' then

               -- Entry is transfer type, put back into free list
               if obDesc.code = "00" then
                  nxtState <= ST_FREE;

               -- Wait until FIFO has enough room for max header size (256 bytes) 
               elsif obHeaderPFull = '0' and axiReadFromCntrl.afull = '0' then
                  nxtState <= ST_REQ;
                  nextReq  <= '1';
               end if;
            end if;

         -- Assert request, wait for ack
         when ST_REQ =>
            nextReq <= '1';
   
            if axiReadFromCntrl.gnt = '1' then
               nxtState  <= ST_READ;
            end if;

         -- Issue read request
         when ST_READ =>
            nextReq   <= '1';
            addrValid <= '1';
            nxtState  <= ST_CHECK;

         -- Check if we are done
         when ST_CHECK =>
          
            -- Done 
            if readPending >= obDesc.length then
               nextReq  <= '0';
               nxtState <= ST_WAIT;

            -- Keep reading
            else
               nextReq  <= '1';
               nxtState <= ST_READ;
            end if;

         -- Wait for all of the data to return
         when ST_WAIT =>
            if rxDone = '1' and rxLast = '1' then
               nxtState <= ST_FREE;
            end if;

         -- Return descriptor to free list
         when ST_FREE =>
            nextFreeWrite <= '1';
            nxtState      <= ST_IDLE;

         when others =>
            nxtState <= ST_IDLE;
      end case;
   end process;

   -----------------------------------------
   -- Read data processing
   -----------------------------------------
   process ( axiClk ) begin
      if rising_edge(axiClk) then
         if axiClkRstInt = '1' then
            header          <= OB_HEADER_FROM_FIFO_INIT_C after TPD_G;
            rxLengthCnt     <= (others=>'0')              after TPD_G;
            rxDone          <= '0'                        after TPD_G;
            rxLast          <= '0'                        after TPD_G;

         -- Receiver Init
         elsif rxInit = '1' then
            header.valid    <= '0'   after TPD_G;
            rxDone          <= '0'   after TPD_G;
            rxLast          <= '0'   after TPD_G;
            rxLengthCnt     <= x"01" after TPD_G;

         -- Read data is valid
         elsif axiReadFromCntrl.rvalid = '1' then
            rxLast <= axiReadFromCntrl.rlast after TPD_G;
            
            -- Output data
            header.code  <= obDesc.code            after TPD_G;
            header.htype <= obDesc.htype           after TPD_G;
            header.data  <= axiReadFromCntrl.rdata after TPD_G;

            -- Write
            header.valid <= not rxDone after TPD_G;

            -- Last qword of the transfer
            if rxLengthCnt = obDesc.length then
               rxDone     <= '1' after TPD_G;
               header.eoh <= '1' after TPD_G;

            -- Increment transfer count
            else
               rxLengthCnt <= rxLengthCnt + 1 after TPD_G;
               header.eoh  <= '0'             after TPD_G;
            end if;
         else
            header.valid <= '0' after TPD_G;
         end if;
      end if;
   end process;


   -----------------------------------------
   -- Output FIFO
   -----------------------------------------
   U_HdrFifo : entity work.Fifo
      generic map (
         TPD_G           => TPD_G,
         RST_POLARITY_G  => '1',
         RST_ASYNC_G     => false,
         GEN_SYNC_FIFO_G => true,
         BRAM_EN_G       => true,
         FWFT_EN_G       => true,
         USE_DSP48_G     => "no",
         USE_BUILT_IN_G  => true,
         XIL_DEVICE_G    => "7SERIES",
         SYNC_STAGES_G   => 3,
         DATA_WIDTH_G    => 72,
         ADDR_WIDTH_G    => PPI_CONFIG_G.obHeaderAddrWidth,
         INIT_G          => "0",
         FULL_THRES_G    => OB_HEADER_FULL_THRESH_C,
         EMPTY_THRES_G   => 1
      ) port map (
         rst                => axiClkRstInt,
         wr_clk             => axiClk,
         wr_en              => header.valid,
         din                => headerDin,
         wr_data_count      => open,
         wr_ack             => open,
         overflow           => open,
         prog_full          => obHeaderPFull,
         almost_full        => open,
         full               => open,
         not_full           => open,
         rd_clk             => axiClk,
         rd_en              => obHeaderToFifo.read,
         dout               => headerDout,
         rd_data_count      => open,
         valid              => obHeaderFromFifo.valid,
         underflow          => open,
         prog_empty         => open,
         almost_empty       => open,
         empty              => open
      );

   -- Connect Inputs
   headerDin(71)           <= '0';
   headerDin(70 downto 69) <= header.code;
   headerDin(68)           <= header.eoh;
   headerDin(67 downto 64) <= header.htype;
   headerDin(63 downto  0) <= header.data;

   -- Connect Outputs
   obHeaderFromFifo.code  <= headerDout(70 downto 69);
   obHeaderFromFifo.eoh   <= headerDout(68);
   obHeaderFromFifo.htype <= headerDout(67 downto 64);
   obHeaderFromFifo.data  <= headerDout(63 downto  0);

end architecture structure;

