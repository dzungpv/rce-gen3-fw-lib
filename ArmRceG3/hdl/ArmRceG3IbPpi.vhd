-------------------------------------------------------------------------------
-- Title         : ARM Based RCE Generation 3, Inbound PPI DMA
-- File          : ArmRceG3IbPpi.vhd
-- Author        : Ryan Herbst, rherbst@slac.stanford.edu
-- Created       : 09/03/2013
-------------------------------------------------------------------------------
-- Description:
-- Inbound PPI DMA controller
-------------------------------------------------------------------------------
-- Copyright (c) 2013 by Ryan Herbst. All rights reserved.
-------------------------------------------------------------------------------
-- Modification history:
-- 04/02/2013: created.
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

entity ArmRceG3IbPpi is
   generic (
      TPD_G      : time    := 1 ns
   );
   port (

      -- Clock
      axiClk                  : in  sl;
      axiClkRst               : in  sl;

      -- AXI HP Master
      axiHpSlaveWriteFromArm  : in  AxiWriteSlaveType;
      axiHpSlaveWriteToArm    : out AxiWriteMasterType;

      -- Inbound Header FIFO
      ibHeaderToFifo          : out IbHeaderToFifoType;
      ibHeaderFromFifo        : in  IbHeaderFromFifoType;

      -- Memory pointer free list write
      ppiPtrWrite             : in  sl;
      ppiPtrData              : in  slv(35 downto 0);

      -- Configuration
      writeDmaCache           : in  slv(3  downto 0);
      ppiOnline               : in  sl;

      -- Completion FIFO
      compFromFifo            : out CompFromFifoType;
      compToFifo              : in  CompToFifoType;

      -- PPI FIFO Interface
      ibPpiClk                : in  sl;
      ibPpiToFifo             : in  IbPpiToFifoType;
      ibPpiFromFifo           : out IbPpiFromFifoType
   );
end ArmRceG3IbPpi;

architecture structure of ArmRceG3IbPpi is

   -- Inbound Descriptor Data
   type IbDescType is record
      addr      : slv(31 downto 0);
      drop      : sl;
      maxLength : slv(31 downto 0);
      compId    : slv(31 downto 0);
      compEn    : sl;
      compIdx   : slv(3  downto 0);
      ready     : sl;
      compReady : sl;
   end record;

   -- Inbound PPI data
   type IbPpiType is record
      data   : slv(63 downto 0);
      eof    : sl;
      ftype  : slv(2 downto 0);
      mgmt   : sl;
      valid  : slv(7 downto 0);
   end record;

   -- States
   type States is ( ST_IDLE, ST_ADDR, ST_WRITE, ST_CHECK, ST_WAIT, ST_DROP, ST_CLEAR );

   -- Local signals
   signal currCompData      : CompFromFifoType;
   signal nextCompWrite     : sl;
   signal ppiPtrRead        : sl;
   signal ppiPtrDout        : slv(35 downto 0);
   signal ppiPtrValid       : sl;
   signal ibPpiFifo         : IbPpiType;
   signal ibPpiHold         : IbPpiType;
   signal ibPpi             : IbPpiType;
   signal ibPpiFifoRead     : sl;
   signal ibPpiRead         : sl;
   signal ibPpiStart        : sl;
   signal ibPpiValid        : sl;
   signal ibPpiShift        : sl;
   signal ibPpiShiftEn      : sl;
   signal ibPpiWrite        : sl;
   signal ibPpiDout         : slv(71 downto 0);
   signal ibPpiDin          : slv(71 downto 0);
   signal ibPpiProgFull     : sl;
   signal ibPpiFull         : sl;
   signal addrValid         : sl;
   signal dataValid         : sl;
   signal dataLast          : sl;
   signal writeAddr         : slv(31 downto 0);
   signal currDone          : sl;
   signal nextDone          : sl;
   signal ackCount          : slv(31 downto 0);
   signal burstCount        : slv(31 downto 0);
   signal wordCount         : slv(3  downto 0);
   signal frameLength       : slv(31 downto 0);
   signal compFifoDin       : slv(35 downto 0);
   signal compFifoDout      : slv(35 downto 0);
   signal payloadEn         : sl;
   signal burstCountEn      : sl;
   signal wordCountEn       : sl;
   signal ibDesc            : IbDescType;
   signal ibDescCount       : slv(1 downto 0);
   signal ibDescClear       : sl;
   signal countReset        : sl;
   signal axiWriteToCntrl   : AxiWriteToCntrlType;
   signal axiWriteFromCntrl : AxiWriteFromCntrlType;
   signal firstSize         : slv(7   downto 0);
   signal currSize          : slv(7   downto 0);
   signal firstLength       : slv(3   downto 0);
   signal currLength        : slv(3   downto 0);
   signal ppiOnlineReg      : slv(1   downto 0);
   signal currState         : States;
   signal nextState         : States;
   signal dbgState          : slv(2 downto 0);

   -- Mark For Debug
   --attribute mark_debug                      : string;
   --attribute mark_debug of currCompData      : signal is "true";
   --attribute mark_debug of nextCompWrite     : signal is "true";
   --attribute mark_debug of ppiPtrRead        : signal is "true";
   --attribute mark_debug of ppiPtrValid       : signal is "true";
   --attribute mark_debug of ibPpiFifo         : signal is "true";
   --attribute mark_debug of ibPpiHold         : signal is "true";
   --attribute mark_debug of ibPpi             : signal is "true";
   --attribute mark_debug of ibPpiFifoRead     : signal is "true";
   --attribute mark_debug of ibPpiRead         : signal is "true";
   --attribute mark_debug of ibPpiStart        : signal is "true";
   --attribute mark_debug of ibPpiValid        : signal is "true";
   --attribute mark_debug of ibPpiShift        : signal is "true";
   --attribute mark_debug of ibPpiShiftEn      : signal is "true";
   --attribute mark_debug of ibPpiWrite        : signal is "true";
   --attribute mark_debug of ibPpiProgFull     : signal is "true";
   --attribute mark_debug of ibPpiFull         : signal is "true";
   --attribute mark_debug of addrValid         : signal is "true";
   --attribute mark_debug of dataValid         : signal is "true";
   --attribute mark_debug of dataLast          : signal is "true";
   --attribute mark_debug of writeAddr         : signal is "true";
   --attribute mark_debug of currDone          : signal is "true";
   --attribute mark_debug of nextDone          : signal is "true";
   --attribute mark_debug of ackCount          : signal is "true";
   --attribute mark_debug of burstCount        : signal is "true";
   --attribute mark_debug of wordCount         : signal is "true";
   --attribute mark_debug of frameLength       : signal is "true";
   --attribute mark_debug of payloadEn         : signal is "true";
   --attribute mark_debug of burstCountEn      : signal is "true";
   --attribute mark_debug of wordCountEn       : signal is "true";
   --attribute mark_debug of ibDesc            : signal is "true";
   --attribute mark_debug of ibDescCount       : signal is "true";
   --attribute mark_debug of ibDescClear       : signal is "true";
   --attribute mark_debug of countReset        : signal is "true";
   --attribute mark_debug of axiWriteToCntrl   : signal is "true";
   --attribute mark_debug of axiWriteFromCntrl : signal is "true";
   --attribute mark_debug of firstSize         : signal is "true";
   --attribute mark_debug of currSize          : signal is "true";
   --attribute mark_debug of firstLength       : signal is "true";
   --attribute mark_debug of currLength        : signal is "true";
   --attribute mark_debug of ppiOnlineReg      : signal is "true";
   --attribute mark_debug of dbgState          : signal is "true";

begin

   -- State Debug
   dbgState <= conv_std_logic_vector(States'POS(currState), 3);

   -----------------------------------------
   -- Receive Control FIFO
   -----------------------------------------
   U_PtrFifo : entity work.FifoSyncBuiltIn 
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => '1',
         FWFT_EN_G      => true,
         USE_DSP48_G    => "no",
         XIL_DEVICE_G   => "7SERIES",
         DATA_WIDTH_G   => 36,
         ADDR_WIDTH_G   => 9,
         FULL_THRES_G   => 1,
         EMPTY_THRES_G  => 1
      ) port map (
         rst          => axiClkRst,
         clk          => axiClk,
         wr_en        => ppiPtrWrite,
         rd_en        => ppiPtrRead,
         din          => ppiPtrData,
         dout         => ppiPtrDout,
         data_count   => open,
         wr_ack       => open,
         valid        => ppiPtrValid,
         overflow     => open,
         underflow    => open,
         prog_full    => open,
         prog_empty   => open,
         almost_full  => open,
         almost_empty => open,
         not_full     => open,
         full         => open,
         empty        => open
      );

   -- Read control
   ppiPtrRead <= ppiPtrValid when ibDescCount /= 3 and ibDescClear = '0' else '0';

   -- Extract descriptor data
   process ( axiClk, axiClkRst ) begin
      if axiClkRst = '1' then
         ibDesc.addr      <= (others=>'0') after TPD_G;
         ibDesc.drop      <= '0'           after TPD_G;
         ibDesc.maxLength <= (others=>'0') after TPD_G;
         ibDesc.compId    <= (others=>'0') after TPD_G;
         ibDesc.compEn    <= '0'           after TPD_G;
         ibDesc.compIdx   <= (others=>'0') after TPD_G;
         ibDesc.ready     <= '0'           after TPD_G;
         ibDesc.compReady <= '0'           after TPD_G;
         ibDescCount      <= (others=>'0') after TPD_G;
      elsif rising_edge(axiClk) then

         -- Reset
         if ibDescClear = '1' then
            ibDesc.addr      <= (others=>'0') after TPD_G;
            ibDesc.drop      <= '0'           after TPD_G;
            ibDesc.maxLength <= (others=>'0') after TPD_G;
            ibDesc.compId    <= (others=>'0') after TPD_G;
            ibDesc.compEn    <= '0'           after TPD_G;
            ibDesc.compIdx   <= (others=>'0') after TPD_G;
            ibDesc.ready     <= '0'           after TPD_G;
            ibDesc.compReady <= '0'           after TPD_G;
            ibDescCount      <= (others=>'0') after TPD_G;

         -- Count up to 3
         elsif ppiPtrRead = '1' and ibDescCount /= 3 then
            ibDescCount <= ibDescCount + 1 after TPD_G;
         
            -- Latch read data
            case ibDescCount is

               -- Word 0, Address
               when "00" => 
                  ibDesc.drop <= ppiPtrDout(32)          after TPD_G;
                  ibDesc.addr <= ppiPtrDout(31 downto 0) after TPD_G;

               -- Word 1, Max Length
               when "01" => 
                  ibDesc.compEn    <= ppiPtrDout(32)          after TPD_G;
                  ibDesc.maxLength <= ppiPtrDout(31 downto 0) after TPD_G;
                  ibDesc.ready     <= '1'                     after TPD_G;

               -- Word 2, comp id and enable
               when "10" => 
                  ibDesc.compIdx   <= ppiPtrDout(35 downto 32) after TPD_G;
                  ibDesc.compId    <= ppiPtrDout(31 downto  0) after TPD_G;
                  ibDesc.compReady <= '1'                      after TPD_G;

               when others =>
            end case;
         end if;
      end if;
   end process;


   -----------------------------------------
   -- Input FIFO
   -----------------------------------------
   -- Assert programmable full when FIFO is half full
   U_PpiFifo : entity work.FifoAsyncBuiltIn 
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => '1',
         FWFT_EN_G      => true,
         USE_DSP48_G    => "no",
         XIL_DEVICE_G   => "7SERIES",
         SYNC_STAGES_G  => 2,
         DATA_WIDTH_G   => 72,
         ADDR_WIDTH_G   => 9,
         FULL_THRES_G   => 255,
         EMPTY_THRES_G  => 1
      ) port map (
         rst                => axiClkRst,
         wr_clk             => ibPpiClk,
         wr_en              => ibPpiWrite,
         din                => ibPpiDin,
         wr_data_count      => open,
         wr_ack             => open,
         overflow           => open,
         prog_full          => ibPpiProgFull,
         almost_full        => open,
         full               => ibPpiFull,
         not_full           => open,
         rd_clk             => axiClk,
         rd_en              => ibPpiFifoRead,
         dout               => ibPpiDout,
         rd_data_count      => open,
         valid              => ibPpiValid,
         underflow          => open,
         prog_empty         => open,
         almost_empty       => open,
         empty              => open
      );

   -- Toggle write destination
   process ( ibPpiClk, axiClkRst ) begin
      if axiClkRst = '1' then
         payloadEn <= '0' after TPD_G;
      elsif rising_edge(ibPpiClk) then
         if ibPpiToFifo.valid = '1' then

            -- Go to header mode on EOF
            if ibPpiToFifo.eof = '1' then
               payloadEn <= '0' after TPD_G;

            -- Go to payload mode on EOH (and not EOF)
            elsif ibPpiToFifo.eoh = '1' then
               payloadEn <= '1' after TPD_G;
            end if;
         end if;
      end if;
   end process;

   -- Local write
   ibPpiWrite <= ibPpiToFifo.valid and payloadEn;

   -- Header write
   ibHeaderToFifo.valid <= ibPpiToFifo.valid and (not payloadEn);
   ibHeaderToFifo.mgmt  <= ibPpiToFifo.mgmt;
   ibHeaderToFifo.htype <= ibPpiToFifo.ftype;
   ibHeaderToFifo.data  <= ibPpiToFifo.data;
   ibHeaderToFifo.err   <= ibPpiToFifo.err and ibPpiToFifo.eof;
   ibHeaderToFifo.eoh   <= ibPpiToFifo.eoh;

   -- Outbound flow control
   ibPpiFromFifo.pause <= ibPpiProgFull or ibHeaderFromFifo.progFull;

   -- Input Data
   ibPpiDin(71)           <= ibPpiToFifo.mgmt;
   ibPpiDin(70 downto 68) <= ibPpiToFifo.ftype;
   ibPpiDin(67)           <= ibPpiToFifo.eof;
   ibPpiDin(66 downto 64) <= ibPpiToFifo.size;
   ibPpiDin(63 downto  0) <= ibPpiToFifo.data;

   -- Output Data
   ibPpiFifo.mgmt  <= ibPpiDout(71);
   ibPpiFifo.ftype <= ibPpiDout(70 downto 68);
   ibPpiFifo.eof   <= ibPpiDout(67);
   ibPpiFifo.valid <= "11111111" when ibPpiDout(66 downto 64) = "111" and ibPpiValid = '1' else 
                      "01111111" when ibPpiDout(66 downto 64) = "110" and ibPpiValid = '1' else 
                      "00111111" when ibPpiDout(66 downto 64) = "101" and ibPpiValid = '1' else 
                      "00011111" when ibPpiDout(66 downto 64) = "100" and ibPpiValid = '1' else 
                      "00001111" when ibPpiDout(66 downto 64) = "011" and ibPpiValid = '1' else 
                      "00000111" when ibPpiDout(66 downto 64) = "010" and ibPpiValid = '1' else 
                      "00000011" when ibPpiDout(66 downto 64) = "001" and ibPpiValid = '1' else 
                      "00000001" when ibPpiDout(66 downto 64) = "000" and ibPpiValid = '1' else 
                      "00000000";
   ibPpiFifo.data  <= ibPpiDout(63 downto  0);

   -- Synchronize the online bit
   process ( ibPpiClk ) begin
      if rising_edge(ibPpiClk) then
         ppiOnlineReg(0) <= ppiOnline       after TPD_G;
         ppiOnlineReg(1) <= ppiOnlineReg(0) after TPD_G;
      end if;
   end process;

   ibPpiFromFifo.online <= ppiOnlineReg(1);

   -----------------------------------------
   -- FIFO Output Byte Reordering
   -----------------------------------------

   -- FIFO register stages
   process ( axiClk, axiClkRst ) begin
      if axiClkRst = '1' then
         ibPpiShiftEn    <= '0'           after TPD_G;
         ibPpiHold.data  <= (others=>'0') after TPD_G; 
         ibPpiHold.eof   <= '0'           after TPD_G;
         ibPpiHold.ftype <= (others=>'0') after TPD_G;
         ibPpiHold.mgmt  <= '0'           after TPD_G;
         ibPpiHold.valid <= (others=>'0') after TPD_G;
         ibPpi.data      <= (others=>'0') after TPD_G;
         ibPpi.eof       <= '0'           after TPD_G;
         ibPpi.ftype     <= (others=>'0') after TPD_G;
         ibPpi.mgmt      <= '0'           after TPD_G;
         ibPpi.valid     <= (others=>'0') after TPD_G;
      elsif rising_edge(axiClk) then

         -- Shift enable
         if ibPpiShift = '1' and ibPpiFifo.eof = '1' then
            ibPpiShiftEn <= '0' after TPD_G;
         elsif ibPpiStart = '1' then
            ibPpiShiftEn <= '1' after TPD_G;
         end if;

         -- Shift
         if ibPpiShift = '1' then

            -- Init
            ibPpiHold       <= ibPpiFifo     after TPD_G;
            ibPpiHold.eof   <= '0'           after TPD_G;
            ibPpiHold.valid <= (others=>'0') after TPD_G;
            ibPpi           <= ibPpiFifo     after TPD_G;
            ibPpi.eof       <= '0'           after TPD_G;
            ibPpi.valid     <= (others=>'0') after TPD_G;

            -- EOF is not sitting on hold register
            if ibPpiHold.eof = '1' then
               ibPpi <= ibPpiHold after TPD_G;

            -- EOF is not sitting on output register or hold register
            elsif ibPpi.eof = '0' then

               -- Determine shift
               case ibDesc.addr(2 downto 0) is

                  -- No shift
                  when "000" =>
                     ibPpi <= ibPpiFifo after TPD_G;

                  -- Shift by 1
                  when "001" =>

                     -- Output register
                     ibPpi.data(63 downto 8)    <= ibPpiFifo.data(55 downto 0)  after TPD_G;
                     ibPpi.valid(7 downto 1)    <= ibPpiFifo.valid(6 downto 0)  after TPD_G;
                     ibPpi.data(7  downto 0)    <= ibPpiHold.data(7  downto 0)  after TPD_G;
                     ibPpi.valid(0)             <= ibPpiHold.valid(0)           after TPD_G;

                     -- Holding register
                     ibPpiHold.data(7 downto 0) <= ibPpiFifo.data(63 downto 56) after TPD_G;
                     ibPpiHold.valid(0)         <= ibPpiFifo.valid(7)           after TPD_G;

                     -- EOF
                     if ibPpiFifo.eof = '1' then
                        if ibPpiFifo.valid(7) /= '0' then
                           ibPpiHold.eof <= '1';
                        else
                           ibPpi.eof <= '1';
                        end if;
                     end if;

                  -- Shift by 2
                  when "010" =>

                     -- Output register
                     ibPpi.data(63 downto 16)    <= ibPpiFifo.data(47 downto 0)  after TPD_G;
                     ibPpi.valid(7 downto 2)     <= ibPpiFifo.valid(5 downto 0)  after TPD_G;
                     ibPpi.data(15 downto 0)     <= ibPpiHold.data(15 downto 0)  after TPD_G;
                     ibPpi.valid(1 downto 0)     <= ibPpiHold.valid(1 downto 0)  after TPD_G;

                     -- Holding register
                     ibPpiHold.data(15 downto 0) <= ibPpiFifo.data(63 downto 48) after TPD_G;
                     ibPpiHold.valid(1 downto 0) <= ibPpiFifo.valid(7 downto 6)  after TPD_G;

                     -- EOF
                     if ibPpiFifo.eof = '1' then
                        if ibPpiFifo.valid(7 downto 6) /= 0 then
                           ibPpiHold.eof <= '1';
                        else
                           ibPpi.eof <= '1';
                        end if;
                     end if;

                  -- Shift by 3
                  when "011" =>

                     -- Output register
                     ibPpi.data(63 downto 24)    <= ibPpiFifo.data(39 downto 0)  after TPD_G;
                     ibPpi.valid(7 downto 3)     <= ibPpiFifo.valid(4 downto 0)  after TPD_G;
                     ibPpi.data(23 downto 0)     <= ibPpiHold.data(23 downto 0)  after TPD_G;
                     ibPpi.valid(2 downto 0)     <= ibPpiHold.valid(2 downto 0)  after TPD_G;

                     -- Holding register
                     ibPpiHold.data(23 downto 0) <= ibPpiFifo.data(63 downto 40) after TPD_G;
                     ibPpiHold.valid(2 downto 0) <= ibPpiFifo.valid(7 downto 5)  after TPD_G;

                     -- EOF
                     if ibPpiFifo.eof = '1' then
                        if ibPpiFifo.valid(7 downto 5) /= 0 then
                           ibPpiHold.eof <= '1';
                        else
                           ibPpi.eof <= '1';
                        end if;
                     end if;

                  -- Shift by 4
                  when "100" =>

                     -- Output register
                     ibPpi.data(63 downto 32)    <= ibPpiFifo.data(31 downto 0)  after TPD_G;
                     ibPpi.valid(7 downto 4)     <= ibPpiFifo.valid(3 downto 0)  after TPD_G;
                     ibPpi.data(31 downto 0)     <= ibPpiHold.data(31 downto 0)  after TPD_G;
                     ibPpi.valid(3 downto 0)     <= ibPpiHold.valid(3 downto 0)  after TPD_G;

                     -- Holding register
                     ibPpiHold.data(31 downto 0) <= ibPpiFifo.data(63 downto 32) after TPD_G;
                     ibPpiHold.valid(3 downto 0) <= ibPpiFifo.valid(7 downto 4)  after TPD_G;

                     -- EOF
                     if ibPpiFifo.eof = '1' then
                        if ibPpiFifo.valid(7 downto 4) /= 0 then
                           ibPpiHold.eof <= '1';
                        else
                           ibPpi.eof <= '1';
                        end if;
                     end if;

                  -- Shift by 5
                  when "101" =>

                     -- Output register
                     ibPpi.data(63 downto 40)    <= ibPpiFifo.data(23 downto 0)  after TPD_G;
                     ibPpi.valid(7 downto 5)     <= ibPpiFifo.valid(2 downto 0)  after TPD_G;
                     ibPpi.data(39 downto 0)     <= ibPpiHold.data(39 downto 0)  after TPD_G;
                     ibPpi.valid(4 downto 0)     <= ibPpiHold.valid(4 downto 0)  after TPD_G;

                     -- Holding register
                     ibPpiHold.data(39 downto 0) <= ibPpiFifo.data(63 downto 24) after TPD_G;
                     ibPpiHold.valid(4 downto 0) <= ibPpiFifo.valid(7 downto 3)  after TPD_G;

                     -- EOF
                     if ibPpiFifo.eof = '1' then
                        if ibPpiFifo.valid(7 downto 3) /= 0 then
                           ibPpiHold.eof <= '1';
                        else
                           ibPpi.eof <= '1';
                        end if;
                     end if;

                  -- Shift by 6
                  when "110" =>

                     -- Output register
                     ibPpi.data(63 downto 48)    <= ibPpiFifo.data(15 downto 0)  after TPD_G;
                     ibPpi.valid(7 downto 6)     <= ibPpiFifo.valid(1 downto 0)  after TPD_G;
                     ibPpi.data(47 downto 0)     <= ibPpiHold.data(47 downto 0)  after TPD_G;
                     ibPpi.valid(5 downto 0)     <= ibPpiHold.valid(5 downto 0)  after TPD_G;

                     -- Holding register
                     ibPpiHold.data(47 downto 0) <= ibPpiFifo.data(63 downto 16) after TPD_G;
                     ibPpiHold.valid(5 downto 0) <= ibPpiFifo.valid(7 downto 2)  after TPD_G;

                     -- EOF
                     if ibPpiFifo.eof = '1' then
                        if ibPpiFifo.valid(7 downto 2) /= 0 then
                           ibPpiHold.eof <= '1';
                        else
                           ibPpi.eof <= '1';
                        end if;
                     end if;

                  -- Shift by 7
                  when "111" =>

                     -- Output register
                     ibPpi.data(63 downto 56)    <= ibPpiFifo.data(7  downto 0)  after TPD_G;
                     ibPpi.valid(7)              <= ibPpiFifo.valid(0)           after TPD_G;
                     ibPpi.data(55 downto 0)     <= ibPpiHold.data(55 downto 0)  after TPD_G;
                     ibPpi.valid(6 downto 0)     <= ibPpiHold.valid(6 downto 0)  after TPD_G;

                     -- Holding register
                     ibPpiHold.data(55 downto 0) <= ibPpiFifo.data(63 downto 8)  after TPD_G;
                     ibPpiHold.valid(6 downto 0) <= ibPpiFifo.valid(7 downto 1)  after TPD_G;

                     -- EOF
                     if ibPpiFifo.eof = '1' then
                        if ibPpiFifo.valid(7 downto 1) /= 0 then
                           ibPpiHold.eof <= '1';
                        else
                           ibPpi.eof <= '1';
                        end if;
                     end if;

                  when others =>
               end case;

            -- Clear EOF
            else 
               ibPpi.eof <= '0' after TPD_G;
            end if;
         end if;
      end if;
   end process;

   -- Control pipeline shift
   ibPpiShift <= '1' when ibPpiRead = '1' or 
                          ( ibPpiShiftEn = '1' and ibPpiValid = '1' and ibPpi.valid = 0 ) else '0';

   -- Control FIFO reads
   ibPpiFifoRead <= ibPpiShift and ibPpiShiftEn;

   -----------------------------------------
   -- AXI Write Controller
   -----------------------------------------
   U_WriteCntrl : entity work.AxiRceG3AxiWriteCntrl 
      generic map (
         TPD_G      => TPD_G,
         CHAN_CNT_G => 1
      ) port map (
         axiClk               => axiClk,
         axiClkRst            => axiClkRst,
         axiSlaveWriteFromArm => axiHpSlaveWriteFromArm,
         axiSlaveWriteToArm   => axiHpSlaveWriteToArm,
         writeDmaCache        => writeDmaCache,
         axiWriteToCntrl(0)   => axiWriteToCntrl,
         axiWriteFromCntrl(0) => axiWriteFromCntrl
      );

   -- AXI write master
   axiWriteToCntrl.req       <= '1';
   axiWriteToCntrl.address   <= writeAddr(31 downto 3);
   axiWriteToCntrl.avalid    <= addrValid;
   --axiWriteToCntrl.id        <= burstCount(2 downto 0);
   axiWriteToCntrl.id        <= "000";
   axiWriteToCntrl.length    <= currLength;
   axiWriteToCntrl.data      <= ibPpi.data;
   axiWriteToCntrl.dvalid    <= dataValid;
   axiWriteToCntrl.dstrobe   <= ibPpi.valid when currDone = '0' else (others=>'0');
   axiWriteToCntrl.last      <= dataLast;

   -----------------------------------------
   -- State Machine
   -----------------------------------------

   -- Determine transfer size to align all transfers to 128 byte boundaries
   -- This initial alignment will ensure that we never cross a 4k boundary
   firstSize(7 downto 3) <= "10000" - ibDesc.addr(6 downto 3);
   firstSize(2 downto 0) <= "000";
   firstLength           <= x"F"  - ibDesc.addr(6 downto 3);
             
   -- Sync states
   process ( axiClk, axiClkRst ) begin
      if axiClkRst = '1' then
         currState              <= ST_IDLE       after TPD_G;
         currDone               <= '0'           after TPD_G;
         writeAddr              <= (others=>'0') after TPD_G;
         burstCount             <= (others=>'0') after TPD_G;
         ackCount               <= (others=>'0') after TPD_G;
         wordCount              <= (others=>'0') after TPD_G;
         frameLength            <= (others=>'0') after TPD_G;
         currCompData.valid     <= '0'           after TPD_G;
         currCompData.index     <= (others=>'0') after TPD_G;
         currCompData.id        <= (others=>'0') after TPD_G;
         currSize               <= (others=>'0') after TPD_G;
         currLength             <= (others=>'0') after TPD_G;
      elsif rising_edge(axiClk) then
         currState  <= nextState     after TPD_G;
         currDone   <= nextDone      after TPD_G;

         -- Write address tracking
         if countReset = '1' then
            writeAddr(31 downto 3)  <= ibDesc.addr(31 downto 3) after TPD_G;
            writeAddr(2  downto 0)  <= "000"                    after TPD_G;
            currSize                <= firstSize                after TPD_G;
            currLength              <= firstLength              after TPD_G;

         -- Stop incrementing address after hitting max length
         elsif burstCountEn = '1' and frameLength /= ibDesc.maxLength then
            writeAddr  <= writeAddr + currSize after TPD_G;
            currSize   <= x"80"                after TPD_G; -- 128
            currLength <= x"F"                 after TPD_G; -- 15
         end if;

         -- Counter to track outstanding writes
         if countReset = '1' then
            burstCount <= (others=>'0') after TPD_G;
         elsif burstCountEn = '1' then
            burstCount <= burstCount + 1 after TPD_G;
         end if;

         -- Counter to track acks
         if countReset = '1' then
            ackCount <= (others=>'0') after TPD_G;
         elsif axiWriteFromCntrl.bvalid = '1' then
            ackCount <= ackCount + 1 after TPD_G;
         end if;

         -- Word count tracking
         if countReset = '1' or dataLast = '1' then
            wordCount <= "0000" after TPD_G;
         elsif wordCountEn = '1' then
            wordCount <= wordCount + 1 after TPD_G;
         end if;

         -- Frame length tracking
         if countReset = '0' then
            frameLength <= (others=>'0') after TPD_G;
         elsif ibPpiRead = '1' then

            -- Stop counting if exceeding max length
            if frameLength /= ibDesc.maxLength then
               frameLength <= frameLength + 1 after TPD_G;
            end if;
         end if;

         -- Completion 
         currCompData.id    <= ibDesc.compId  after TPD_G;
         currCompData.index <= ibDesc.compIdx after TPD_G;
         currCompData.valid <= nextCompWrite  after TPD_G;

      end if;
   end process;

   -- ASync states
   process ( currState, ibDesc, currDone, burstCount, ackCount, 
             ibPpi, wordCount, axiWriteFromCntrl, currLength ) begin

      -- Init signals
      nextState     <= currState;
      nextDone      <= currDone;
      burstCountEn  <= '0';
      wordCountEn   <= '0';
      dataValid     <= '0';
      dataLast      <= '0';
      countReset    <= '0';
      ibDescClear   <= '0';
      ibPpiStart    <= '0';
      ibPpiRead     <= '0';
      nextCompWrite <= '0';
      addrValid     <= '0';

      -- State machine
      case currState is 

         -- Idle
         when ST_IDLE =>
            countReset <= '1';

            -- Wait for ib desc to be valid
            if ibDesc.ready = '1' then
               ibPpiStart <= '1';

               -- Drop is set
               if ibDesc.drop = '1' then
                  nextState  <= ST_DROP;
               else
                  nextState  <= ST_ADDR;
               end if;
            end if;

         -- Address
         when ST_ADDR =>

            -- Wait for controller to be ready
            if axiWriteFromCntrl.afull = '0' then
               addrValid  <= '1';
               nextState  <= ST_WRITE;
            end if;

         -- Write data
         when ST_WRITE =>

            -- Assert data valid
            dataValid <= uOr(ibPpi.valid) or currDone;

            -- Data is moving
            if (ibPpi.valid /= 0 or currDone = '1') then

               -- Assert read
               ibPpiRead   <= not currDone;
               wordCountEn <= '1';
               
               -- EOF is set
               if ibPpi.eof = '1' then
                  nextDone <= '1';
               end if;

               -- Last word
               if wordCount = currLength then
                  dataLast  <= '1';
                  nextState <= ST_CHECK;
               end if;
            end if;

         -- Check state, de-assert request
         when ST_CHECK =>
            burstCountEn <= '1';
            nextDone     <= '0';

            -- Transfer is done
            if currDone = '1' then
               nextState <= ST_WAIT;
            else
               nextState <= ST_ADDR;
            end if;

         -- Wait for writes to complete
         when ST_WAIT =>

            -- Writes have completed
            if burstCount = ackCount and ibDesc.compReady = '1' then
               nextCompWrite <= ibDesc.compEn;
               nextState     <= ST_CLEAR;
            end if;

         -- Drop data
         when ST_DROP =>

            -- Flush FIFO
            ibPpiRead <= uOr(ibPpi.valid);

            -- EOF
            if ibPpi.eof = '1' then
               nextState   <= ST_CLEAR;
            end if;

         -- Clear Descriptor
         when ST_CLEAR =>
            ibDescClear <= '1';
            nextState   <= ST_IDLE;

         when others =>
            nextState <= ST_IDLE;
      end case;
   end process;


   -----------------------------------------
   -- Completion FIFO
   -----------------------------------------
   U_CompFifo : entity work.FifoSync
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => '1',
         RST_ASYNC_G    => false,
         BRAM_EN_G      => false,  -- Use Dist Ram
         FWFT_EN_G      => true,
         USE_DSP48_G    => "no",
         ALTERA_RAM_G   => "M512",
         DATA_WIDTH_G   => 36,
         ADDR_WIDTH_G   => 4,
         FULL_THRES_G   => 15,
         EMPTY_THRES_G  => 1
      ) port map (
         rst                => axiClkRst,
         clk                => axiClk,
         wr_en              => currCompData.valid,
         din                => compFifoDin,
         data_count         => open,
         wr_ack             => open,
         overflow           => open,
         prog_full          => open,
         almost_full        => open,
         full               => open,
         not_full           => open,
         rd_en              => compToFifo.read,
         dout               => compFifoDout,
         valid              => compFromFifo.valid,
         underflow          => open,
         prog_empty         => open,
         almost_empty       => open,
         empty              => open
      );

   -- Completion FIFO input  
   compFifoDin(31 downto  0) <= currCompData.id;
   compFifoDin(35 downto 32) <= currCompData.index;

   -- Completion FIFO output  
   compFromFifo.id    <= compFifoDout(31 downto  0);
   compFromFifo.index <= compFifoDout(35 downto 32);

end architecture structure;

