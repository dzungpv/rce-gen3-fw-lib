-------------------------------------------------------------------------------
-- Title         : ARM Based RCE Generation 3, Package File
-- File          : ArmRceG3Pkg.vhd
-- Author        : Ryan Herbst, rherbst@slac.stanford.edu
-- Created       : 04/02/2013
-------------------------------------------------------------------------------
-- Description:
-- Package file for ARM based rce generation 3 processor core.
-------------------------------------------------------------------------------
-- Copyright (c) 2013 by Ryan Herbst. All rights reserved.
-------------------------------------------------------------------------------
-- Modification history:
-- 04/02/2013: created.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.numeric_std.all;

package ArmRceG3Pkg is

   ----------------------------------
   -- Constants
   ----------------------------------
   constant TPD_G : time := 0.1 ns;

   ----------------------------------
   -- Types
   ----------------------------------

   subtype Word4Type is std_logic_vector(3 downto 0);
   type Word4Array   is array (integer range<>) of Word4Type;

   subtype Word15Type is std_logic_vector(14 downto 0);
   type Word15Array   is array (integer range<>) of Word15Type;

   subtype Word16Type is std_logic_vector(15 downto 0);
   type Word16Array   is array (integer range<>) of Word16Type;

   subtype Word32Type is std_logic_vector(31 downto 0);
   type Word32Array   is array (integer range<>) of Word32Type;

   subtype Word36Type is std_logic_vector(35 downto 0);
   type Word36Array   is array (integer range<>) of Word36Type;

   subtype Word64Type is std_logic_vector(63 downto 0);
   type Word64Array   is array (integer range<>) of Word64Type;

   subtype Word72Type is std_logic_vector(71 downto 0);
   type Word72Array   is array (integer range<>) of Word72Type;

   subtype Word128Type is std_logic_vector(127 downto 0);
   type Word128Array   is array (integer range<>) of Word128Type;

   --------------------------------------------------------
   -- AXI bus, read master signal record
   --------------------------------------------------------

   -- Base Record
   type AxiReadMasterType is record

      -- Read Address channel
      arvalid               : std_logic;
      araddr                : std_logic_vector(31 downto 0);
      arid                  : std_logic_vector(11 downto 0); -- 12 for master GP, 6 for slave GP, 3 for ACP, 6 for HP
      arlen                 : std_logic_vector(3  downto 0);
      arsize                : std_logic_vector(2  downto 0);
      arburst               : std_logic_vector(1  downto 0);
      arlock                : std_logic_vector(1  downto 0);
      arprot                : std_logic_vector(2  downto 0);
      arcache               : std_logic_vector(3  downto 0);
      arqos                 : std_logic_vector(3  downto 0);
      aruser                : std_logic_vector(4  downto 0); -- ACP

      -- Read data channel
      rready                : std_logic;

      -- Control 
      rdissuecap1_en        : std_logic;                     -- HP0-3

   end record;

   -- Initialization constants
   constant AxiReadMasterInit : AxiReadMasterType := ( 
      arvalid               => '0',
      araddr                => x"00000000",
      arid                  => x"000",
      arlen                 => "0000",
      arsize                => "000",
      arburst               => "00",
      arlock                => "00",
      arprot                => "000",
      arcache               => "0000",
      arqos                 => "0000",
      aruser                => "00000",
      rready                => '0',
      rdissuecap1_en        => '0'
   );

   -- Vector
   type AxiReadMasterVector is array (integer range<>) of AxiReadMasterType;


   --------------------------------------------------------
   -- AXI bus, read slave signal record
   --------------------------------------------------------

   -- Base Record
   type AxiReadSlaveType is record

      -- Read Address channel
      arready               : std_logic;

      -- Read data channel
      rdata                 : std_logic_vector(63 downto 0); -- 32 bits for GP0/GP1 
      rlast                 : std_logic;
      rvalid                : std_logic;
      rid                   : std_logic_vector(11 downto 0); -- 12 for master GP, 6 for slave GP, 3 for ACP, 6 for HP
      rresp                 : std_logic_vector(1  downto 0);

      -- Status
      racount               : std_logic_vector(2  downto 0); -- HP0-3
      rcount                : std_logic_vector(7  downto 0); -- HP0-3

   end record;

   -- Initialization constants
   constant AxiReadSlaveInit : AxiReadSlaveType := ( 
      arready               => '0',
      rdata                 => x"0000000000000000",
      rlast                 => '0',
      rvalid                => '0',
      rid                   => x"000",
      rresp                 => "00",
      racount               => "000",
      rcount                => x"00"
   );

   -- Vector
   type AxiReadSlaveVector is array (integer range<>) of AxiReadSlaveType;


   --------------------------------------------------------
   -- AXI bus, write master signal record
   --------------------------------------------------------

   -- Base Record
   type AxiWriteMasterType is record

      -- Write address channel
      awvalid               : std_logic;
      awaddr                : std_logic_vector(31 downto 0);
      awid                  : std_logic_vector(11 downto 0); -- 12 for master GP, 6 for slave GP, 3 for ACP, 6 for HP
      awlen                 : std_logic_vector(3  downto 0);
      awsize                : std_logic_vector(2  downto 0);
      awburst               : std_logic_vector(1  downto 0);
      awlock                : std_logic_vector(1  downto 0);
      awcache               : std_logic_vector(3  downto 0);
      awprot                : std_logic_vector(2  downto 0);
      awqos                 : std_logic_vector(3  downto 0);
      awuser                : std_logic_vector(4  downto 0); -- ACP

      -- Write data channel
      wdata                 : std_logic_vector(63 downto 0); -- 32 bits for GP0/GP1
      wlast                 : std_logic;
      wvalid                : std_logic;
      wid                   : std_logic_vector(11 downto 0); -- 12 for master GP, 6 for slave GP, 3 for ACP, 6 for HP
      wstrb                 : std_logic_vector(7  downto 0); -- 4 for GPs

      -- Write ack channel
      bready                : std_logic;

      -- Control
      wrissuecap1_en        : std_logic;                     -- HP0-3

   end record;

   -- Initialization constants
   constant AxiWriteMasterInit : AxiWriteMasterType := ( 
      awvalid               => '0',
      awaddr                => x"00000000",
      awid                  => x"000",
      awlen                 => "0000",
      awsize                => "000",
      awburst               => "00",
      awlock                => "00",
      awcache               => "0000",
      awprot                => "000",
      awqos                 => "0000",
      awuser                => "00000",
      wdata                 => x"0000000000000000",
      wlast                 => '0',
      wvalid                => '0',
      wid                   => x"000",
      wstrb                 => "00000000",
      bready                => '0',
      wrissuecap1_en        => '0'
   );

   -- Vector
   type AxiWriteMasterVector is array (integer range<>) of AxiWriteMasterType;


   --------------------------------------------------------
   -- AXI bus, write slave signal record
   --------------------------------------------------------

   -- Base Record
   type AxiWriteSlaveType is record

      -- Write address channel
      awready               : std_logic;

      -- Write data channel
      wready                : std_logic;

      -- Write ack channel
      bresp                 : std_logic_vector(1  downto 0);
      bvalid                : std_logic;
      bid                   : std_logic_vector(11 downto 0); -- 12 for master GP, 6 for slave GP, 3 for ACP, 6 for HP

      -- Status
      wacount               : std_logic_vector(5  downto 0); -- HP0-3
      wcount                : std_logic_vector(7  downto 0); -- HP0-3

   end record;

   -- Initialization constants
   constant AxiWriteSlaveInit : AxiWriteSlaveType := ( 
      awready               => '0',
      wready                => '0',
      bresp                 => "00",
      bvalid                => '0',
      bid                   => x"000",
      wacount               => "000000",
      wcount                => x"00"
   );

   -- Vector
   type AxiWriteSlaveVector is array (integer range<>) of AxiWriteSlaveType;

   --------------------------------------------------------
   -- Local Bus Master
   --------------------------------------------------------

   -- Base Record
   type LocalBusMasterType is record
      addr                    : std_logic_vector(31 downto 0); -- Held during enire cycle
      addrValid               : std_logic; -- Pulsed for one cycle
      readEnable              : std_logic; -- Pulsed for one cycle
      writeEnable             : std_logic; -- Pulsed for one cycle
      writeData               : std_logic_vector(31 downto 0);
   end record;

   -- Initialization constants
   constant LocalBusMasterInit : LocalBusMasterType := ( 
      addr                  => x"00000000",
      addrValid             => '0',
      readEnable            => '0',
      writeEnable           => '0',
      writeData             => x"00000000"
   );

   -- Vector
   type LocalBusMasterVector is array (integer range<>) of LocalBusMasterType;

   --------------------------------------------------------
   -- Local Bus Slave
   --------------------------------------------------------

   -- Base Record
   type LocalBusSlaveType is record
      readValid               : std_logic;
      readData                : std_logic_vector(31 downto 0);
   end record;

   -- Initialization constants
   constant LocalBusSlaveInit : LocalBusSlaveType := ( 
      readValid             => '0',
      readData              => x"00000000"
   );

   -- Vector
   type LocalBusSlaveVector is array (integer range<>) of LocalBusSlaveType;

   --------------------------------------------------------
   -- Write FIFO, To Fifo Record
   --------------------------------------------------------

   -- Base Record
   type WriteFifoToFifoType is record
      data   : std_logic_vector(71 downto 0);
      write  : std_logic;
   end record;

   -- Initialization constants
   constant WriteFifoToFifoInit : WriteFifoToFifoType := ( 
      data     => x"000000000000000000",
      write    => '0'
   );

   -- Vector
   type WriteFifoToFifoVector is array (integer range<>) of WriteFifoToFifoType;

   --------------------------------------------------------
   -- Write FIFO, From Fifo Record
   --------------------------------------------------------

   -- Base Record
   type WriteFifoFromFifoType is record
      full       : std_logic;
      almostFull : std_logic;
   end record;

   -- Initialization constants
   constant WriteFifoFromFifoInit : WriteFifoFromFifoType := ( 
      full       => '0',
      almostFull => '0' 
   );

   -- Vector
   type WriteFifoFromFifoVector is array (integer range<>) of WriteFifoFromFifoType;

   --------------------------------------------------------
   -- Read FIFO, To Fifo Record
   --------------------------------------------------------

   -- Base Record
   type ReadFifoToFifoType is record
      read : std_logic;
   end record;

   -- Initialization constants
   constant ReadFifoToFifoInit : ReadFifoToFifoType := ( 
      read  => '0'
   );

   -- Vector
   type ReadFifoToFifoVector is array (integer range<>) of ReadFifoToFifoType;

   --------------------------------------------------------
   -- Read FIFO, From Fifo Record
   --------------------------------------------------------

   -- Base Record
   type ReadFifoFromFifoType is record
      valid  : std_logic;
      data   : std_logic_vector(71 downto 0);
   end record;

   -- Initialization constants
   constant ReadFifoFromFifoInit : ReadFifoFromFifoType := ( 
      valid      => '0',
      data       => x"000000000000000000"
   );

   -- Vector
   type ReadFifoFromFifoVector is array (integer range<>) of ReadFifoFromFifoType;

   --------------------------------------------------------
   -- Ethernet From ARM
   --------------------------------------------------------

   -- Base Record
   type EthFromArmType is record
      enetGmiiTxEn        : std_logic;
      enetGmiiTxEr        : std_logic;
      enetMdioMdc         : std_logic;
      enetMdioO           : std_logic;
      enetMdioT           : std_logic;
      enetPtpDelayReqRx   : std_logic;
      enetPtpDelayReqTx   : std_logic;
      enetPtpPDelayReqRx  : std_logic;
      enetPtpPDelayReqTx  : std_logic;
      enetPtpPDelayRespRx : std_logic;
      enetPtpPDelayRespTx : std_logic;
      enetPtpSyncFrameRx  : std_logic;
      enetPtpSyncFrameTx  : std_logic;
      enetSofRx           : std_logic;
      enetSofTx           : std_logic;
      enetGmiiTxD         : std_logic_vector(7 downto 0);  
   end record;

   -- Initialization constants
   constant EthFromArmInit : EthFromArmType := ( 
      enetGmiiTxEn        => '0',
      enetGmiiTxEr        => '0',
      enetMdioMdc         => '0',
      enetMdioO           => '0',
      enetMdioT           => '0',
      enetPtpDelayReqRx   => '0',
      enetPtpDelayReqTx   => '0',
      enetPtpPDelayReqRx  => '0',
      enetPtpPDelayReqTx  => '0',
      enetPtpPDelayRespRx => '0',
      enetPtpPDelayRespTx => '0',
      enetPtpSyncFrameRx  => '0',
      enetPtpSyncFrameTx  => '0',
      enetSofRx           => '0',
      enetSofTx           => '0',
      enetGmiiTxD         => (others=>'0')
   );

   -- Vector
   type EthFromArmVector is array (integer range<>) of EthFromArmType;

   --------------------------------------------------------
   -- Ethernet To ARM
   --------------------------------------------------------

   -- Base Record
   type EthToArmType is record
      enetGmiiCol   : std_logic;
      enetGmiiCrs   : std_logic;
      enetGmiiRxClk : std_logic;
      enetGmiiRxDv  : std_logic;
      enetGmiiRxEr  : std_logic;
      enetGmiiTxClk : std_logic;
      enetMdioI     : std_logic;
      enetExtInitN  : std_logic;
      enetGmiiRxd   : std_logic_vector(7 downto 0);  
   end record;

   -- Initialization constants
   constant EthToArmInit : EthToArmType := ( 
      enetGmiiCol   => '0',
      enetGmiiCrs   => '0',
      enetGmiiRxClk => '0',
      enetGmiiRxDv  => '0',
      enetGmiiRxEr  => '0',
      enetGmiiTxClk => '0',
      enetMdioI     => '0',
      enetExtInitN  => '0',
      enetGmiiRxd   => (others=>'0')
   );

   -- Vector
   type EthToArmVector is array (integer range<>) of EthToArmType;

end ArmRceG3Pkg;
