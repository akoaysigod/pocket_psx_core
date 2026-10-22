-- Pocket build: trimmed GTE (same behaviour as gte.vhd, smaller); it declares entity gte so it replaces
-- gte.vhd in the Pocket file list (pocket/src/fpga/psx_pocket.qip), like savestates_reset.vhd and mdec_black.vhd.
library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

library mem;
use STD.textio.all;

use work.pGTE.all;
use work.pGTEs.all;

entity gte is
   port 
   (
      clk1x                : in  std_logic;
      clk2x                : in  std_logic;
      clk2xIndex           : in  std_logic;
      ce                   : in  std_logic;
      reset                : in  std_logic;
      
      WIDESCREEN           : in  std_logic_vector(1 downto 0);
      TURBO                : in  std_logic;
      
      gte_busy             : out std_logic;
      gte_readAddr         : in  unsigned(5 downto 0);
      gte_readData         : out unsigned(31 downto 0);
      gte_readEna          : in  std_logic;
      gte_writeAddr_in     : in  unsigned(5 downto 0);
      gte_writeData_in     : in  unsigned(31 downto 0);
      gte_writeEna_in      : in  std_logic; 
      gte_cmdData          : in  unsigned(31 downto 0);
      gte_cmdEna           : in  std_logic;
      
      loading_savestate    : in  std_logic;
      SS_reset             : in  std_logic;
      SS_DataWrite         : in  std_logic_vector(31 downto 0);
      SS_Adr               : in  unsigned(5 downto 0);
      SS_wren              : in  std_logic;
      SS_rden              : in  std_logic;
      SS_DataRead          : out std_logic_vector(31 downto 0);
      SS_idle              : out std_logic;
      
      debug_firstGTE       : out std_logic
   );
end entity;

architecture arch of gte is
   
   -- input
   signal gte_writeAddr : unsigned(5 downto 0);
   signal gte_writeData : unsigned(31 downto 0);
   signal gte_writeEna  : std_logic;

   -- GTE data regs
   signal REG_V0X  : signed(15 downto 0);
   signal REG_V0Y  : signed(15 downto 0);
   signal REG_V0Z  : signed(15 downto 0);
   signal REG_V1X  : signed(15 downto 0);
   signal REG_V1Y  : signed(15 downto 0);
   signal REG_V1Z  : signed(15 downto 0);
   signal REG_V2X  : signed(15 downto 0);
   signal REG_V2Y  : signed(15 downto 0);
   signal REG_V2Z  : signed(15 downto 0);
   signal REG_RGBC : unsigned(31 downto 0);
   signal REG_OTZ  : unsigned(15 downto 0);
   signal REG_IR0  : signed(15 downto 0);
   signal REG_IR1  : signed(15 downto 0);
   signal REG_IR2  : signed(15 downto 0);
   signal REG_IR3  : signed(15 downto 0);
   signal REG_SX0  : signed(15 downto 0);
   signal REG_SY0  : signed(15 downto 0);
   signal REG_SX1  : signed(15 downto 0);
   signal REG_SY1  : signed(15 downto 0);
   signal REG_SX2  : signed(15 downto 0);
   signal REG_SY2  : signed(15 downto 0);
   signal REG_SZ0  : unsigned(15 downto 0);
   signal REG_SZ1  : unsigned(15 downto 0);
   signal REG_SZ2  : unsigned(15 downto 0);
   signal REG_SZ3  : unsigned(15 downto 0);
   signal REG_RGB0 : unsigned(31 downto 0);
   signal REG_RGB1 : unsigned(31 downto 0);
   signal REG_RGB2 : unsigned(31 downto 0);
   signal REG_RES1 : unsigned(31 downto 0);
   signal REG_MAC0 : signed(31 downto 0);
   signal REG_MAC1 : signed(31 downto 0);
   signal REG_MAC2 : signed(31 downto 0);
   signal REG_MAC3 : signed(31 downto 0);
   signal REG_IRGB : unsigned(14 downto 0);
   signal REG_ORGB : unsigned(14 downto 0);
   signal REG_LZCR : signed(31 downto 0);
   
   -- GTE control regs
   signal REG_RT11  : signed(15 downto 0);
   signal REG_RT12  : signed(15 downto 0);
   signal REG_RT21  : signed(15 downto 0);
   signal REG_RT23  : signed(15 downto 0);
   signal REG_RT31  : signed(15 downto 0);
   signal REG_RT32  : signed(15 downto 0);
   signal REG_RT33  : signed(15 downto 0);
   signal REG_LL11  : signed(15 downto 0);
   signal REG_LL12  : signed(15 downto 0);
   signal REG_LL13  : signed(15 downto 0);
   signal REG_LL21  : signed(15 downto 0);
   signal REG_LL22  : signed(15 downto 0);
   signal REG_LL23  : signed(15 downto 0);
   signal REG_LL31  : signed(15 downto 0);
   signal REG_LL32  : signed(15 downto 0);
   signal REG_LL33  : signed(15 downto 0);
   signal REG_LC11  : signed(15 downto 0);
   signal REG_LC12  : signed(15 downto 0);
   signal REG_LC13  : signed(15 downto 0);
   signal REG_LC21  : signed(15 downto 0);
   signal REG_LC22  : signed(15 downto 0);
   signal REG_LC23  : signed(15 downto 0);
   signal REG_LC31  : signed(15 downto 0);
   signal REG_LC32  : signed(15 downto 0);
   signal REG_LC33  : signed(15 downto 0);
   signal REG_DQA   : signed(15 downto 0);
   signal REG_FLAG  : unsigned(31 downto 0);
   
   -- widescreen
   signal IR1aspect     : signed(16 downto 0);
   signal IR1aspect_1   : signed(16 downto 0);
   signal IR1aspect_2   : signed(16 downto 0);
  
   -- calculation
   type tstate is
   (
      IDLE,
      CALC_RTPS,
      CALC_NCLIP,
      CALC_OP,
      CALC_DPCS,
      CALC_INTPL,
      CALC_MVMVA,
      CALC_NCDS,
      CALC_CDP,
      CALC_NCDT,
      CALC_NCCS,
      CALC_CC,
      CALC_NCS,
      CALC_NCT,
      CALC_SQR,
      CALC_DPCL,
      CALC_DPCT,
      CALC_AVSZ3,
      CALC_AVSZ4,
      CALC_RTPT,
      CALC_GPF,
      CALC_GPL,
      CALC_NCCT
   );
   signal state : tstate := IDLE;
   
   -- Pocket: the last calcStep of every command (the batch commands only get there in their last pass, the
   -- earlier passes restart at step 0), so the end of a command is one compare instead of a branch per command
   function lastStep(s : tstate) return integer is
   begin
      case (s) is
         when CALC_RTPS  => return 25;
         when CALC_RTPT  => return 41;
         when CALC_NCLIP => return 11;
         when CALC_OP    => return 7;
         when CALC_DPCS  => return 10;
         when CALC_DPCT  => return 10;
         when CALC_INTPL => return 10;
         when CALC_MVMVA => return 10;
         when CALC_NCDS  => return 33;
         when CALC_NCDT  => return 39;
         when CALC_CDP   => return 20;
         when CALC_NCCS  => return 29;
         when CALC_NCCT  => return 37;
         when CALC_CC    => return 16;
         when CALC_NCS   => return 22;
         when CALC_NCT   => return 28;
         when CALC_SQR   => return 5;
         when CALC_DPCL  => return 10;
         when CALC_AVSZ3 => return 5;
         when CALC_AVSZ4 => return 7;
         when CALC_GPF   => return 4;
         when CALC_GPL   => return 5;
         when others     => return 63;
      end case;
   end function;
   
   signal calcStep         : integer range 0 to 63;
   signal batchCount       : integer range 0 to 2;
   signal turbomode        : std_logic := '0';      
         
   signal cmdShift         : std_logic;
   signal cmdsatIR         : std_logic;
   signal cmdMM            : unsigned(1 downto 0);
   signal cmdMV            : unsigned(1 downto 0);
   signal cmdTV            : unsigned(1 downto 0);
   
   signal calcColor        : unsigned(23 downto 0);
   signal pushRGBfromMAC   : std_logic := '0';
   signal setOTZ           : std_logic := '0';
   signal pushSZandDivide  : std_logic := '0';
   signal pushSXY          : std_logic := '0';
   
   signal REG_IR2_1        : signed(15 downto 0);
   signal REG_IR2_2        : signed(15 downto 0);
   
   signal matrix00         : signed(15 downto 0);
   signal matrix01         : signed(15 downto 0);
   signal matrix02         : signed(15 downto 0);
   signal matrix10         : signed(15 downto 0);
   signal matrix11         : signed(15 downto 0);
   signal matrix12         : signed(15 downto 0);
   signal matrix20         : signed(15 downto 0);
   signal matrix21         : signed(15 downto 0);
   signal matrix22         : signed(15 downto 0);
            
   signal vector0          : signed(15 downto 0);
   signal vector1          : signed(15 downto 0);
   signal vector2          : signed(15 downto 0);
         
   signal translate0       : signed(31 downto 0);
   signal translate1       : signed(31 downto 0);
   signal translate2       : signed(31 downto 0);
         
   signal shiftcode        : unsigned(1 downto 0);
   
   -- MACs
   signal MAC0req          : tMAC0req;
   signal mac0_result      : signed(34 downto 0);
   signal mac0_writeback   : std_logic;
   signal ir0_result       : signed(15 downto 0);
   signal ir0_writeback    : std_logic;
   signal mac0Last         : signed(34 downto 0);
   signal flagMac0UF       : std_logic;
   signal flagMac0OF       : std_logic;
   signal flagIR0          : std_logic;
   
   signal MAC1req          : tMAC123sreq;
   signal mac1_result      : signed(31 downto 0);
   signal mac1_writeback   : std_logic;
   signal ir1_result       : signed(15 downto 0);
   signal ir1_writeback    : std_logic;
   signal mac1Last         : signed(44 downto 0);
   signal flagMac1UF       : std_logic;
   signal flagMac1OF       : std_logic;
   signal flagIR1          : std_logic;
   
   signal MAC2req          : tMAC123sreq;
   signal mac2_result      : signed(31 downto 0);
   signal mac2_writeback   : std_logic;
   signal ir2_result       : signed(15 downto 0);
   signal ir2_writeback    : std_logic;
   signal mac2Last         : signed(44 downto 0);
   signal flagMac2UF       : std_logic;
   signal flagMac2OF       : std_logic;
   signal flagIR2          : std_logic;
   
   signal MAC3req          : tMAC123sreq;
   signal mac3_result      : signed(31 downto 0);
   signal mac3_writeback   : std_logic;
   signal ir3_result       : signed(15 downto 0);
   signal ir3_writeback    : std_logic;
   signal mac3Last         : signed(44 downto 0);
   signal mac3Shifted      : signed(31 downto 0);
   signal flagMac3UF       : std_logic;
   signal flagMac3OF       : std_logic;
   signal flagIR3          : std_logic;
   
   -- divide
   signal div_trigger      : std_logic;
   signal div_lhs          : unsigned(15 downto 0);
   signal div_rhs          : unsigned(15 downto 0);
   signal div_result       : unsigned(16 downto 0);
   signal div_Error        : std_logic;
  
   -- debug
   signal debugCnt         : unsigned(31 downto 0);
   
   -- register readback: registers written only by the CPU (V0-V2, RGBC, RES1 and the control
   -- registers except FLAG) are read back from a block-RAM copy holding their readback value,
   -- written together with the register. Only the registers that commands update stay in the
   -- readback multiplexer. shadowValid returns 0 until a register is written after reset.
   type tShadowRam is array(0 to 63) of std_logic_vector(31 downto 0);
   signal shadowRam        : tShadowRam;
   signal shadowValid      : std_logic_vector(63 downto 0) := (others => '0');
   signal shadowWe         : std_logic;
   signal shadowRe         : std_logic;
   signal shadowWd         : unsigned(31 downto 0);
   signal shadowQ          : unsigned(31 downto 0) := (others => '0');

   -- Pocket: matrix (RT/LL/LC) and translation (TR/BK/FC) storage. The datapath reads the matrix and
   -- translation operands straight from MLAB copies of these control registers, addressed by a
   -- registered select code, instead of latching them into registers. Control registers are only
   -- written by CTC2, which the CPU stalls while the GTE is busy, so the selected values cannot change
   -- while a command uses them. The "garbage matrix" entries derived from data registers (RGBC, IR0)
   -- are still latched. A register reads 0 until written after reset (shadowValid).
   type tMatQ  is array(0 to 8) of std_logic_vector(15 downto 0);
   type tTrQ   is array(0 to 2) of std_logic_vector(31 downto 0);
   type tCode9 is array(0 to 8) of std_logic_vector(1 downto 0);  -- std_logic_vector: an array of unsigned would make "&" ambiguous
   type tCode3 is array(0 to 2) of std_logic_vector(1 downto 0);
   signal matQ             : tMatQ;
   signal trQ              : tTrQ;
   signal matCode          : tCode9 := (others => "00");
   signal trCode           : tCode3 := (others => "00");
   -- Pocket: OFX, OFY, H, DQB, ZSF3, ZSF4 (control registers 56-62 except DQA) are only read one at a time
   -- (MAC0's offset / Z factor, the divider's H), so they come from one RAM addressed by ofCode = register - 56,
   -- which is set one step before each use (ofCode block below); a register reads 0 until written after reset
   signal ofCode           : std_logic_vector(2 downto 0) := (others => '0');
   signal ofQ              : std_logic_vector(31 downto 0);
   signal ofVal            : signed(31 downto 0);
   signal ofWe             : std_logic;
   -- Pocket (timing): the falling-edge M10Ks (translation, OF) write from registered copies of the CPU write
   -- (one clk2x after the write cycle) instead of from the CPU's write signals through the decode, which left
   -- only half a clk2x cycle; nothing reads them in between (writes stall while the GTE is busy)
   signal trWe             : std_logic_vector(2 downto 0);
   signal trWe_r           : std_logic_vector(2 downto 0) := (others => '0');
   signal ofWe_r           : std_logic := '0';
   signal m10kWa           : std_logic_vector(5 downto 0) := (others => '0');
   signal m10kWd           : std_logic_vector(31 downto 0) := (others => '0');
   signal matrix3_00       : signed(15 downto 0) := (others => '0');
   -- Pocket: MVMVA's "garbage matrix" (MX = 3): rows 1 and 2 are RT13 and RT22, read from the RT copies of
   -- elements 2 and 4 (their own values are not used then), so no flip-flop copies of RT13 / RT22
   signal matGarbage       : std_logic := '0';
   signal matRT13          : signed(15 downto 0);
   signal matRT22          : signed(15 downto 0);
   signal matrix3_01       : signed(15 downto 0) := (others => '0');
   signal matrix3_02       : signed(15 downto 0) := (others => '0');

   -- element e of matrix m (0 = RT, 1 = LL, 2 = LC) is half (e mod 2) of control word 32 + 8 m + e / 2
   function matValid(v : std_logic_vector(63 downto 0); code : unsigned(1 downto 0); e : integer) return boolean is
   begin
      return v(32 + 8 * to_integer(code) + e / 2) = '1';
   end function;
   -- element t of translation vector m (0 = TR, 1 = BK, 2 = FC) is control word 37 + 8 m + t
   function trValid(v : std_logic_vector(63 downto 0); code : unsigned(1 downto 0); t : integer) return boolean is
   begin
      return v(37 + 8 * to_integer(code) + t) = '1';
   end function;
   signal readFromShadow   : std_logic := '0';
   signal readShadowValid  : std_logic := '0';
   signal readData_mux     : unsigned(31 downto 0) := (others => '0');

   function isShadowed(a : unsigned(5 downto 0)) return boolean is
      variable i : integer range 0 to 63;
   begin
      i := to_integer(a);
      return (i <= 6 or i = 23 or i = 30 or (i >= 32 and i <= 62));  -- Pocket: + LZCS (only read back)
   end function;

   -- readback value of a shadowed register after the CPU writes d to it
   function shadowValue(a : unsigned(5 downto 0); d : unsigned(31 downto 0)) return unsigned is
   begin
      case (to_integer(a)) is
         when 1 | 3 | 5 | 36 | 44 | 52 | 58 | 59 | 61 | 62 => return unsigned(resize(signed(d(15 downto 0)), 32));
         when others => return d;
      end case;
   end function;

   -- savestates
   signal SSreadAddr       : unsigned(5 downto 0);
   signal SSrden           : std_logic;
   signal SS_readData      : std_logic_vector(31 downto 0);
  
begin 

   gte_writeAddr <= SS_Adr                 when (loading_savestate = '1') else gte_writeAddr_in;
   gte_writeData <= unsigned(SS_DataWrite) when (loading_savestate = '1') else gte_writeData_in;
   gte_writeEna  <= SS_wren                when (loading_savestate = '1') else gte_writeEna_in; 

   -- same conditions as the register writes/reads in the main process
   shadowWe <= '1' when (not (reset = '1' and loading_savestate = '0') and (ce = '1' or loading_savestate = '1') and
                         gte_writeEna = '1' and clk2xIndex = '1' and isShadowed(gte_writeAddr)) else '0';
   shadowRe <= '1' when (not (reset = '1' and loading_savestate = '0') and (ce = '1' or loading_savestate = '1') and
                         gte_readEna = '1') else '0';
   shadowWd <= shadowValue(gte_writeAddr, gte_writeData);

   process (clk2x)
   begin
      if rising_edge(clk2x) then
         if (shadowWe = '1') then
            shadowRam(to_integer(gte_writeAddr)) <= std_logic_vector(shadowWd);
         end if;
         if (shadowRe = '1') then
            shadowQ <= unsigned(shadowRam(to_integer(gte_readAddr)));
         end if;
      end if;
   end process;

   gte_readData <= readData_mux when (readFromShadow = '0') else
                   shadowQ      when (readShadowValid = '1') else
                   (others => '0');

   gmatram : for e in 0 to 8 generate
      signal we : std_logic;
      signal wd : std_logic_vector(15 downto 0);
   begin
      we <= '1' when (shadowWe = '1' and gte_writeAddr(5) = '1' and gte_writeAddr(4 downto 3) /= "11" and to_integer(gte_writeAddr(2 downto 0)) = e / 2) else '0';
      wd <= std_logic_vector(gte_writeData(15 downto 0)) when (e mod 2 = 0) else std_logic_vector(gte_writeData(31 downto 16));
      imatram : entity mem.RamMLAB
      generic map (width => 16, widthad => 2)
      port map (inclock => clk2x, wren => we, data => wd, wraddress => std_logic_vector(gte_writeAddr(4 downto 3)),
                rdaddress => matCode(e), q => matQ(e));
   end generate;

   gtrram : for t in 0 to 2 generate
   begin
      trWe(t) <= '1' when (shadowWe = '1' and gte_writeAddr(5) = '1' and gte_writeAddr(4 downto 3) /= "11" and to_integer(gte_writeAddr(2 downto 0)) = 5 + t) else '0';
      itrram : entity mem.RamM10Kn  -- Pocket: M10K on the falling edge instead of MLAB (frees LABs)
      generic map (width => 32, widthad => 2)
      port map (inclock => clk2x, wren => trWe_r(t), data => m10kWd, wraddress => m10kWa(4 downto 3),
                rdaddress => trCode(t), q => trQ(t));
   end generate;

   ofWe <= '1' when (shadowWe = '1' and gte_writeAddr(5 downto 3) = "111") else '0';
   iofram : entity mem.RamM10Kn
   generic map (width => 32, widthad => 3)
   port map (inclock => clk2x, wren => ofWe_r, data => m10kWd, wraddress => m10kWa(2 downto 0),
             rdaddress => ofCode, q => ofQ);

   process (clk2x)
   begin
      if rising_edge(clk2x) then
         trWe_r <= trWe;
         ofWe_r <= ofWe;
         m10kWa <= std_logic_vector(gte_writeAddr);
         m10kWd <= std_logic_vector(gte_writeData);
      end if;
   end process;
   ofVal <= signed(ofQ) when (shadowValid(56 + to_integer(unsigned(ofCode))) = '1') else (others => '0');

   matRT13  <= signed(matQ(2)) when matValid(shadowValid, "00", 2) else (others => '0');   -- matCode(2) = RT while matGarbage
   matRT22  <= signed(matQ(4)) when matValid(shadowValid, "00", 4) else (others => '0');   -- matCode(4) = RT while matGarbage
   matrix00 <= matrix3_00 when (matGarbage = '1') else signed(matQ(0)) when matValid(shadowValid, unsigned(matCode(0)), 0) else (others => '0');
   matrix01 <= matrix3_01 when (matGarbage = '1') else signed(matQ(1)) when matValid(shadowValid, unsigned(matCode(1)), 1) else (others => '0');
   matrix02 <= matrix3_02 when (matGarbage = '1') else signed(matQ(2)) when matValid(shadowValid, unsigned(matCode(2)), 2) else (others => '0');
   matrix10 <= matRT13    when (matGarbage = '1') else signed(matQ(3)) when matValid(shadowValid, unsigned(matCode(3)), 3) else (others => '0');
   matrix11 <= matRT13    when (matGarbage = '1') else signed(matQ(4)) when matValid(shadowValid, unsigned(matCode(4)), 4) else (others => '0');
   matrix12 <= matRT13    when (matGarbage = '1') else signed(matQ(5)) when matValid(shadowValid, unsigned(matCode(5)), 5) else (others => '0');
   matrix20 <= matRT22    when (matGarbage = '1') else signed(matQ(6)) when matValid(shadowValid, unsigned(matCode(6)), 6) else (others => '0');
   matrix21 <= matRT22    when (matGarbage = '1') else signed(matQ(7)) when matValid(shadowValid, unsigned(matCode(7)), 7) else (others => '0');
   matrix22 <= matRT22    when (matGarbage = '1') else signed(matQ(8)) when matValid(shadowValid, unsigned(matCode(8)), 8) else (others => '0');

   translate0 <= (others => '0') when (trCode(0) = "11") else signed(trQ(0)) when trValid(shadowValid, unsigned(trCode(0)), 0) else (others => '0');
   translate1 <= (others => '0') when (trCode(1) = "11") else signed(trQ(1)) when trValid(shadowValid, unsigned(trCode(1)), 1) else (others => '0');
   translate2 <= (others => '0') when (trCode(2) = "11") else signed(trQ(2)) when trValid(shadowValid, unsigned(trCode(2)), 2) else (others => '0');
   
   process (clk2x)
      variable leadCountData : unsigned(31 downto 0);
      variable colorNewR     : unsigned(7 downto 0);
      variable colorNewG     : unsigned(7 downto 0);
      variable colorNewB     : unsigned(7 downto 0);
      variable matrix00_ld : std_logic;
      variable matrix00_c : integer range 0 to 3;
      variable matrix01_ld : std_logic;
      variable matrix01_c : integer range 0 to 3;
      variable matrix02_ld : std_logic;
      variable matrix02_c : integer range 0 to 3;
      variable matrix10_ld : std_logic;
      variable matrix10_c : integer range 0 to 3;
      variable matrix11_ld : std_logic;
      variable matrix11_c : integer range 0 to 3;
      variable matrix12_ld : std_logic;
      variable matrix12_c : integer range 0 to 3;
      variable matrix20_ld : std_logic;
      variable matrix20_c : integer range 0 to 3;
      variable matrix21_ld : std_logic;
      variable matrix21_c : integer range 0 to 3;
      variable matrix22_ld : std_logic;
      variable matrix22_c : integer range 0 to 3;
      variable vector0_ld : std_logic;
      variable vector0_c : integer range 0 to 3;
      variable vector1_ld : std_logic;
      variable vector1_c : integer range 0 to 3;
      variable vector2_ld : std_logic;
      variable vector2_c : integer range 0 to 3;
      variable translate0_ld : std_logic;
      variable translate0_c : integer range 0 to 3;
      variable translate1_ld : std_logic;
      variable translate1_c : integer range 0 to 3;
      variable translate2_ld : std_logic;
      variable translate2_c : integer range 0 to 3;
      variable mac0_mode : integer range 0 to 2;
      variable mac0_c1 : integer range 0 to 13;
      variable mac0_c2 : integer range 0 to 5;
      variable mac0_c3 : integer range 0 to 3;
      variable mac0_fl : std_logic_vector(0 to 6);
      variable mac0_v1 : signed(16 downto 0);
      variable mac0_v2 : signed(17 downto 0);
      variable mac0_v3 : signed(31 downto 0);
      variable mac1_mode : integer range 0 to 2;
      variable mac1_ca : integer range 0 to 5;
      variable mac1_cb : integer range 0 to 7;
      variable mac1_cv : integer range 0 to 6;
      variable mac1_csh : integer range 0 to 3;
      variable mac1_cadd : integer range 0 to 2;
      variable mac1_fl : std_logic_vector(0 to 9);
      variable mac1_va : signed(15 downto 0);
      variable mac1_vb : signed(15 downto 0);
      variable mac1_vv : signed(31 downto 0);
      variable mac1_vsh : unsigned(1 downto 0);
      variable mac1_vadd : signed(44 downto 0);
      variable mac2_mode : integer range 0 to 2;
      variable mac2_ca : integer range 0 to 5;
      variable mac2_cb : integer range 0 to 7;
      variable mac2_cv : integer range 0 to 6;
      variable mac2_csh : integer range 0 to 3;
      variable mac2_cadd : integer range 0 to 2;
      variable mac2_fl : std_logic_vector(0 to 9);
      variable mac2_va : signed(15 downto 0);
      variable mac2_vb : signed(15 downto 0);
      variable mac2_vv : signed(31 downto 0);
      variable mac2_vsh : unsigned(1 downto 0);
      variable mac2_vadd : signed(44 downto 0);
      variable mac3_mode : integer range 0 to 2;
      variable mac3_ca : integer range 0 to 5;
      variable mac3_cb : integer range 0 to 7;
      variable mac3_cv : integer range 0 to 6;
      variable mac3_csh : integer range 0 to 3;
      variable mac3_cadd : integer range 0 to 2;
      variable mac3_fl : std_logic_vector(0 to 9);
      variable mac3_va : signed(15 downto 0);
      variable mac3_vb : signed(15 downto 0);
      variable mac3_vv : signed(31 downto 0);
      variable mac3_vsh : unsigned(1 downto 0);
      variable mac3_vadd : signed(44 downto 0);
   begin
      if rising_edge(clk2x) then

         -- select codes are combinational within the cycle: default them so no storage is inferred
         matrix00_ld := '0'; matrix00_c := 0; matrix01_ld := '0'; matrix01_c := 0; matrix02_ld := '0'; matrix02_c := 0; matrix10_ld := '0'; matrix10_c := 0; matrix11_ld := '0'; matrix11_c := 0; matrix12_ld := '0'; matrix12_c := 0; matrix20_ld := '0'; matrix20_c := 0; matrix21_ld := '0'; matrix21_c := 0; matrix22_ld := '0'; matrix22_c := 0; vector0_ld := '0'; vector0_c := 0; vector1_ld := '0'; vector1_c := 0; vector2_ld := '0'; vector2_c := 0; translate0_ld := '0'; translate0_c := 0; translate1_ld := '0'; translate1_c := 0; translate2_ld := '0'; translate2_c := 0;
         mac0_mode := 0; mac1_mode := 0; mac2_mode := 0; mac3_mode := 0;
         mac0_c1 := 0; mac0_c2 := 0; mac0_c3 := 0; mac0_fl := (others => '0');
         mac0_v1 := (others => '0'); mac0_v2 := (others => '0'); mac0_v3 := (others => '0');
         mac1_ca := 0; mac1_cb := 0; mac1_cv := 0; mac1_csh := 0; mac1_cadd := 0; mac1_fl := (others => '0');
         mac1_va := (others => '0'); mac1_vb := (others => '0'); mac1_vv := (others => '0'); mac1_vsh := (others => '0'); mac1_vadd := (others => '0');
         mac2_ca := 0; mac2_cb := 0; mac2_cv := 0; mac2_csh := 0; mac2_cadd := 0; mac2_fl := (others => '0');
         mac2_va := (others => '0'); mac2_vb := (others => '0'); mac2_vv := (others => '0'); mac2_vsh := (others => '0'); mac2_vadd := (others => '0');
         mac3_ca := 0; mac3_cb := 0; mac3_cv := 0; mac3_csh := 0; mac3_cadd := 0; mac3_fl := (others => '0');
         mac3_va := (others => '0'); mac3_vb := (others => '0'); mac3_vv := (others => '0'); mac3_vsh := (others => '0'); mac3_vadd := (others => '0');
      
         case (WIDESCREEN) is
            when "01"   => IR1aspect <= resize((resize(REG_IR1 & "000", 21)  + resize(REG_IR1 & "00", 21)  + resize(REG_IR1 & '0', 21) ) / 16, 17);   -- * (8 + 4 + 2) / 16 -> ~3:2
            when "10"   => IR1aspect <= resize((resize(REG_IR1 & "000", 21)  + resize(REG_IR1 & "00", 21)  + resize(REG_IR1      , 21) ) / 16, 17);   -- * (8 + 4 + 1) / 16 -> ~5:3
            when "11"   => IR1aspect <= resize((resize(REG_IR1 & "000", 21)  + resize(REG_IR1 & "00", 21)                              ) / 16, 17);   -- * (8 + 4)     / 16 -> 16:9
            when others => IR1aspect <= resize(REG_IR1, 17);
         end case;
      
         turbomode <= TURBO;
      
         if (reset = '1' and loading_savestate = '0') then
         
            shadowValid <= (others => '0');
            state    <= IDLE;
         
            gte_busy <= '0';
            
            debugCnt <= (others => '0');

            REG_V0X  <= (others => '0');
            REG_V0Y  <= (others => '0');
            REG_V0Z  <= (others => '0');
            REG_V1X  <= (others => '0');
            REG_V1Y  <= (others => '0');
            REG_V1Z  <= (others => '0');
            REG_V2X  <= (others => '0');
            REG_V2Y  <= (others => '0');
            REG_V2Z  <= (others => '0');
            REG_RGBC <= (others => '0');
            REG_OTZ  <= (others => '0');
            REG_IR0  <= (others => '0');
            REG_IR1  <= (others => '0');
            REG_IR2  <= (others => '0');
            REG_IR3  <= (others => '0');
            REG_SX0  <= (others => '0');
            REG_SY0  <= (others => '0');
            REG_SX1  <= (others => '0');
            REG_SY1  <= (others => '0');
            REG_SX2  <= (others => '0');
            REG_SY2  <= (others => '0');
            REG_SZ0  <= (others => '0');
            REG_SZ1  <= (others => '0');
            REG_SZ2  <= (others => '0');
            REG_SZ3  <= (others => '0');
            REG_RGB0 <= (others => '0');
            REG_RGB1 <= (others => '0');
            REG_RGB2 <= (others => '0');
            REG_RES1 <= (others => '0');
            REG_MAC0 <= (others => '0');
            REG_MAC1 <= (others => '0');
            REG_MAC2 <= (others => '0');
            REG_MAC3 <= (others => '0');
            REG_IRGB <= (others => '0');
            REG_ORGB <= (others => '0');
            REG_LZCR <= (others => '0');
            
            REG_RT11 <= (others => '0');
            REG_RT12 <= (others => '0');
            REG_RT21 <= (others => '0');
            REG_RT23 <= (others => '0');
            REG_RT31 <= (others => '0');
            REG_RT32 <= (others => '0');
            REG_RT33 <= (others => '0');
            REG_LL11 <= (others => '0');
            REG_LL12 <= (others => '0');
            REG_LL13 <= (others => '0');
            REG_LL21 <= (others => '0');
            REG_LL22 <= (others => '0');
            REG_LL23 <= (others => '0');
            REG_LL31 <= (others => '0');
            REG_LL32 <= (others => '0');
            REG_LL33 <= (others => '0');
            REG_LC11 <= (others => '0');
            REG_LC12 <= (others => '0');
            REG_LC13 <= (others => '0');
            REG_LC21 <= (others => '0');
            REG_LC22 <= (others => '0');
            REG_LC23 <= (others => '0');
            REG_LC31 <= (others => '0');
            REG_LC32 <= (others => '0');
            REG_LC33 <= (others => '0');
            REG_DQA  <= (others => '0');
            REG_FLAG <= (others => '0');
            
         elsif (ce = '1' or loading_savestate = '1') then
         
            MAC0req.trigger <= '0';
            MAC1req.trigger <= '0';
            MAC2req.trigger <= '0';
            MAC3req.trigger <= '0';
            
            div_trigger     <= '0';
            pushRGBfromMAC  <= '0';
            setOTZ          <= '0';
            pushSZandDivide <= '0';
            pushSXY         <= '0';
            
            if (gte_readEna = '1') then
               readFromShadow  <= '0';
               readShadowValid <= shadowValid(to_integer(gte_readAddr));
               if (isShadowed(gte_readAddr)) then
                  readFromShadow <= '1';
               end if;
               case (to_integer(gte_readAddr)) is
                  when 07 => readData_mux <= x"0000" & REG_OTZ;
                  when 08 => readData_mux <= unsigned(resize(REG_IR0, 32));
                  when 09 => readData_mux <= unsigned(resize(REG_IR1, 32));
                  when 10 => readData_mux <= unsigned(resize(REG_IR2, 32));
                  when 11 => readData_mux <= unsigned(resize(REG_IR3, 32));
                  when 12 => readData_mux <= unsigned(REG_SY0 & REG_SX0);
                  when 13 => readData_mux <= unsigned(REG_SY1 & REG_SX1);
                  when 14 => readData_mux <= unsigned(REG_SY2 & REG_SX2);
                  when 15 => readData_mux <= unsigned(REG_SY2 & REG_SX2);
                  when 16 => readData_mux <= x"0000" & REG_SZ0;
                  when 17 => readData_mux <= x"0000" & REG_SZ1;
                  when 18 => readData_mux <= x"0000" & REG_SZ2;
                  when 19 => readData_mux <= x"0000" & REG_SZ3;
                  when 20 => readData_mux <= REG_RGB0;
                  when 21 => readData_mux <= REG_RGB1;
                  when 22 => readData_mux <= REG_RGB2;
                  when 24 => readData_mux <= unsigned(REG_MAC0);
                  when 25 => readData_mux <= unsigned(REG_MAC1);
                  when 26 => readData_mux <= unsigned(REG_MAC2);
                  when 27 => readData_mux <= unsigned(REG_MAC3);
                  when 28 | 29 => 
                     readData_mux(31 downto 15) <= (others => '0');
                     if (REG_IR1 < 0) then readData_mux( 4 downto  0) <= "00000"; elsif (REG_IR1(15 downto 7) > 31) then readData_mux( 4 downto  0) <= "11111"; else readData_mux( 4 downto  0) <= unsigned(REG_IR1(11 downto 7)); end if;
                     if (REG_IR2 < 0) then readData_mux( 9 downto  5) <= "00000"; elsif (REG_IR2(15 downto 7) > 31) then readData_mux( 9 downto  5) <= "11111"; else readData_mux( 9 downto  5) <= unsigned(REG_IR2(11 downto 7)); end if;
                     if (REG_IR3 < 0) then readData_mux(14 downto 10) <= "00000"; elsif (REG_IR3(15 downto 7) > 31) then readData_mux(14 downto 10) <= "11111"; else readData_mux(14 downto 10) <= unsigned(REG_IR3(11 downto 7)); end if;
   
                  when 31 => readData_mux <= unsigned(REG_LZCR);
                  when 63 => readData_mux <= REG_FLAG;
                  when others => null;
               end case;
            end if;
         
            if (gte_writeEna = '1' and clk2xIndex = '1') then
               if (isShadowed(gte_writeAddr)) then
                  shadowValid(to_integer(gte_writeAddr)) <= '1';
               end if;
            
               case (to_integer(gte_writeAddr)) is
                  when 00 => REG_V0X <= signed(gte_writeData(15 downto 0)); REG_V0Y <= signed(gte_writeData(31 downto 16));
                  when 01 => REG_V0Z <= signed(gte_writeData(15 downto 0));
                  when 02 => REG_V1X <= signed(gte_writeData(15 downto 0)); REG_V1Y <= signed(gte_writeData(31 downto 16));
                  when 03 => REG_V1Z <= signed(gte_writeData(15 downto 0));
                  when 04 => REG_V2X <= signed(gte_writeData(15 downto 0)); REG_V2Y <= signed(gte_writeData(31 downto 16));
                  when 05 => REG_V2Z <= signed(gte_writeData(15 downto 0));
                  when 06 => REG_RGBC <= gte_writeData;
                  when 07 => REG_OTZ  <= gte_writeData(15 downto 0);
                  when 08 => REG_IR0  <= signed(gte_writeData(15 downto 0));
                  when 09 => REG_IR1  <= signed(gte_writeData(15 downto 0));
                  when 10 => REG_IR2  <= signed(gte_writeData(15 downto 0));
                  when 11 => REG_IR3  <= signed(gte_writeData(15 downto 0));
                  when 12 => REG_SX0  <= signed(gte_writeData(15 downto 0)); REG_SY0 <= signed(gte_writeData(31 downto 16));
                  when 13 => REG_SX1  <= signed(gte_writeData(15 downto 0)); REG_SY1 <= signed(gte_writeData(31 downto 16));
                  when 14 => REG_SX2  <= signed(gte_writeData(15 downto 0)); REG_SY2 <= signed(gte_writeData(31 downto 16));
                  when 15 => 
                     if (loading_savestate = '0') then
                        REG_SX2  <= signed(gte_writeData(15 downto 0)); REG_SY2 <= signed(gte_writeData(31 downto 16));
                        REG_SX1  <= REG_SX2; REG_SY1 <= REG_SY2;
                        REG_SX0  <= REG_SX1; REG_SY0 <= REG_SY1;
                     end if;
                  when 16 => REG_SZ0  <= gte_writeData(15 downto 0);
                  when 17 => REG_SZ1  <= gte_writeData(15 downto 0);
                  when 18 => REG_SZ2  <= gte_writeData(15 downto 0);
                  when 19 => REG_SZ3  <= gte_writeData(15 downto 0);
                  when 20 => REG_RGB0 <= gte_writeData;
                  when 21 => REG_RGB1 <= gte_writeData;
                  when 22 => REG_RGB2 <= gte_writeData;
                  when 23 => REG_RES1 <= gte_writeData;
                  when 24 => REG_MAC0 <= signed(gte_writeData);
                  when 25 => REG_MAC1 <= signed(gte_writeData);
                  when 26 => REG_MAC2 <= signed(gte_writeData);
                  when 27 => REG_MAC3 <= signed(gte_writeData);
                  when 28 => 
                     REG_IRGB <= gte_writeData(14 downto 0);
                     if (loading_savestate = '0') then
                        REG_IR1  <= signed("0000" & gte_writeData( 4 downto  0) & "0000000");
                        REG_IR2  <= signed("0000" & gte_writeData( 9 downto  5) & "0000000");
                        REG_IR3  <= signed("0000" & gte_writeData(14 downto 10) & "0000000");
                     end if;
                  when 29 => -- read only
                  when 30 =>
                     leadCountData := gte_writeData;
                     if (gte_writeData(31) = '1') then
                        leadCountData := not gte_writeData;
                     end if;
                     REG_LZCR <= signed(to_unsigned(32, 32));
                     for i in 0 to 31 loop
                        if (leadCountData(i) = '1') then
                           REG_LZCR <= signed(to_unsigned(31 - i, 32));
                        end if;
                     end loop;
                     
                  when 31 => -- read only
                  when 32 => REG_RT11 <= signed(gte_writeData(15 downto 0)); REG_RT12 <= signed(gte_writeData(31 downto 16));
                  when 33 => REG_RT21 <= signed(gte_writeData(31 downto 16));
                  when 34 => REG_RT23 <= signed(gte_writeData(31 downto 16));
                  when 35 => REG_RT31 <= signed(gte_writeData(15 downto 0)); REG_RT32 <= signed(gte_writeData(31 downto 16));
                  when 36 => REG_RT33 <= signed(gte_writeData(15 downto 0));
                  when 40 => REG_LL11 <= signed(gte_writeData(15 downto 0)); REG_LL12 <= signed(gte_writeData(31 downto 16));
                  when 41 => REG_LL13 <= signed(gte_writeData(15 downto 0)); REG_LL21 <= signed(gte_writeData(31 downto 16));
                  when 42 => REG_LL22 <= signed(gte_writeData(15 downto 0)); REG_LL23 <= signed(gte_writeData(31 downto 16));
                  when 43 => REG_LL31 <= signed(gte_writeData(15 downto 0)); REG_LL32 <= signed(gte_writeData(31 downto 16));
                  when 44 => REG_LL33 <= signed(gte_writeData(15 downto 0));
                  when 48 => REG_LC11 <= signed(gte_writeData(15 downto 0)); REG_LC12 <= signed(gte_writeData(31 downto 16));
                  when 49 => REG_LC13 <= signed(gte_writeData(15 downto 0)); REG_LC21 <= signed(gte_writeData(31 downto 16));
                  when 50 => REG_LC22 <= signed(gte_writeData(15 downto 0)); REG_LC23 <= signed(gte_writeData(31 downto 16));
                  when 51 => REG_LC31 <= signed(gte_writeData(15 downto 0)); REG_LC32 <= signed(gte_writeData(31 downto 16));
                  when 52 => REG_LC33 <= signed(gte_writeData(15 downto 0));
                  when 59 => REG_DQA  <= signed(gte_writeData(15 downto 0));
                  when 63 => 
                     REG_FLAG(30 downto 12) <= gte_writeData(30 downto 12);
                     REG_FLAG(31) <= '0';
                     if ((gte_writeData(30 downto 12) and to_unsigned(16#7F87E#, 19)) > 0) then  -- bit 30..23 and 18..13
                        REG_FLAG(31) <= '1';
                     end if;
                  when others => null;
               end case;
            
            end if;
            
            -- calculation
            calcStep <= calcStep + 1; 
            
            debug_firstGTE <= '0';
            
            case (state) is
            
               when IDLE =>
                  calcStep   <= 0;
                  batchCount <= 0;
                  if (gte_cmdEna = '1' and clk2xIndex = '1') then
                     gte_busy <= '1';
                     REG_FLAG <= (others => '0');
                     cmdShift <= gte_cmdData(19);
                     cmdsatIR <= gte_cmdData(10);
                     cmdMM    <= gte_cmdData(18 downto 17);
                     cmdMV    <= gte_cmdData(16 downto 15);
                     cmdTV    <= gte_cmdData(14 downto 13);
                     case (to_integer(gte_cmdData(5 downto 0))) is
                        when 16#01# => state <= CALC_RTPS;
                                       translate0_ld := '1'; translate0_c := 0; translate1_ld := '1'; translate1_c := 0; translate2_ld := '1'; translate2_c := 0;
                                       matrix00_ld := '1'; matrix00_c := 0; matrix01_ld := '1'; matrix01_c := 0; matrix02_ld := '1'; matrix02_c := 0;
                                       matrix10_ld := '1'; matrix10_c := 0; matrix11_ld := '1'; matrix11_c := 0; matrix12_ld := '1'; matrix12_c := 0;
                                       matrix20_ld := '1'; matrix20_c := 0; matrix21_ld := '1'; matrix21_c := 0; matrix22_ld := '1'; matrix22_c := 0;
                                       vector0_ld := '1'; vector0_c := 0; vector1_ld := '1'; vector1_c := 0; vector2_ld := '1'; vector2_c := 0;
                        when 16#06# => state <= CALC_NCLIP; 
                        when 16#0C# => state <= CALC_OP;
                                       matrix00_ld := '1'; matrix00_c := 0; matrix01_ld := '1'; matrix01_c := 0; matrix02_ld := '1'; matrix02_c := 0;
                                       matrix10_ld := '1'; matrix10_c := 0; matrix11_ld := '1'; matrix11_c := 0; matrix12_ld := '1'; matrix12_c := 0;
                                       matrix20_ld := '1'; matrix20_c := 0; matrix21_ld := '1'; matrix21_c := 0; matrix22_ld := '1'; matrix22_c := 0;
                        when 16#10# => state <= CALC_DPCS; calcColor <= REG_RGBC(23 downto 0);
                                       translate0_ld := '1'; translate0_c := 2; translate1_ld := '1'; translate1_c := 2; translate2_ld := '1'; translate2_c := 2;
                        when 16#11# => state <= CALC_INTPL;
                                       translate0_ld := '1'; translate0_c := 2; translate1_ld := '1'; translate1_c := 2; translate2_ld := '1'; translate2_c := 2;
                        when 16#12# => state <= CALC_MVMVA;
                                    case (gte_cmdData(18 downto 17)) is
                                       when "00" => matrix00_ld := '1'; matrix00_c := 0; matrix01_ld := '1'; matrix01_c := 0; matrix02_ld := '1'; matrix02_c := 0;
                                                    matrix10_ld := '1'; matrix10_c := 0; matrix11_ld := '1'; matrix11_c := 0; matrix12_ld := '1'; matrix12_c := 0;
                                                    matrix20_ld := '1'; matrix20_c := 0; matrix21_ld := '1'; matrix21_c := 0; matrix22_ld := '1'; matrix22_c := 0;
                                       when "01" => matrix00_ld := '1'; matrix00_c := 1; matrix01_ld := '1'; matrix01_c := 1; matrix02_ld := '1'; matrix02_c := 1;
                                                    matrix10_ld := '1'; matrix10_c := 1; matrix11_ld := '1'; matrix11_c := 1; matrix12_ld := '1'; matrix12_c := 1;
                                                    matrix20_ld := '1'; matrix20_c := 1; matrix21_ld := '1'; matrix21_c := 1; matrix22_ld := '1'; matrix22_c := 1;
                                       when "10" => matrix00_ld := '1'; matrix00_c := 2; matrix01_ld := '1'; matrix01_c := 2; matrix02_ld := '1'; matrix02_c := 2;
                                                    matrix10_ld := '1'; matrix10_c := 2; matrix11_ld := '1'; matrix11_c := 2; matrix12_ld := '1'; matrix12_c := 2;
                                                    matrix20_ld := '1'; matrix20_c := 2; matrix21_ld := '1'; matrix21_c := 2; matrix22_ld := '1'; matrix22_c := 2;
                                       when "11" => matrix00_ld := '1'; matrix00_c := 3; 
                                                    matrix01_ld := '1'; matrix01_c := 3; 
                                                    matrix02_ld := '1'; matrix02_c := 3;
                                                    matrix10_ld := '1'; matrix10_c := 3; matrix11_ld := '1'; matrix11_c := 3; matrix12_ld := '1'; matrix12_c := 3;
                                                    matrix20_ld := '1'; matrix20_c := 3; matrix21_ld := '1'; matrix21_c := 3; matrix22_ld := '1'; matrix22_c := 3;
                                       when others => null;
                                    end case;
                        
                                    case (gte_cmdData(16 downto 15)) is
                                       when "00" => vector0_ld := '1'; vector0_c := 0; vector1_ld := '1'; vector1_c := 0; vector2_ld := '1'; vector2_c := 0;
                                       when "01" => vector0_ld := '1'; vector0_c := 1; vector1_ld := '1'; vector1_c := 1; vector2_ld := '1'; vector2_c := 1;
                                       when "10" => vector0_ld := '1'; vector0_c := 2; vector1_ld := '1'; vector1_c := 2; vector2_ld := '1'; vector2_c := 2;
                                       when "11" => vector0_ld := '1'; vector0_c := 3; vector1_ld := '1'; vector1_c := 3; vector2_ld := '1'; vector2_c := 3;
                                       when others => null;
                                    end case;
                        
                                    case (gte_cmdData(14 downto 13)) is
                                       when "00" => translate0_ld := '1'; translate0_c := 0; translate1_ld := '1'; translate1_c := 0; translate2_ld := '1'; translate2_c := 0;
                                       when "01" => translate0_ld := '1'; translate0_c := 1; translate1_ld := '1'; translate1_c := 1; translate2_ld := '1'; translate2_c := 1;
                                       when "10" => translate0_ld := '1'; translate0_c := 2; translate1_ld := '1'; translate1_c := 2; translate2_ld := '1'; translate2_c := 2;
                                       when "11" => translate0_ld := '1'; translate0_c := 3;     translate1_ld := '1'; translate1_c := 3;     translate2_ld := '1'; translate2_c := 3;
                                       when others => null;
                                    end case;
                     
                        when 16#13# => state <= CALC_NCDS;
                                       translate0_ld := '1'; translate0_c := 1; translate1_ld := '1'; translate1_c := 1; translate2_ld := '1'; translate2_c := 1;
                        when 16#14# => state <= CALC_CDP;
                                       translate0_ld := '1'; translate0_c := 1; translate1_ld := '1'; translate1_c := 1; translate2_ld := '1'; translate2_c := 1;
                                       matrix00_ld := '1'; matrix00_c := 2; matrix01_ld := '1'; matrix01_c := 2; matrix02_ld := '1'; matrix02_c := 2;
                                       matrix10_ld := '1'; matrix10_c := 2; matrix11_ld := '1'; matrix11_c := 2; matrix12_ld := '1'; matrix12_c := 2;
                                       matrix20_ld := '1'; matrix20_c := 2; matrix21_ld := '1'; matrix21_c := 2; matrix22_ld := '1'; matrix22_c := 2;
                        when 16#16# => state <= CALC_NCDT;
                                       translate0_ld := '1'; translate0_c := 1; translate1_ld := '1'; translate1_c := 1; translate2_ld := '1'; translate2_c := 1;
                        when 16#1B# => state <= CALC_NCCS;
                                       translate0_ld := '1'; translate0_c := 1; translate1_ld := '1'; translate1_c := 1; translate2_ld := '1'; translate2_c := 1;
                        when 16#1C# => state <= CALC_CC;
                                       translate0_ld := '1'; translate0_c := 1; translate1_ld := '1'; translate1_c := 1; translate2_ld := '1'; translate2_c := 1;
                                       matrix00_ld := '1'; matrix00_c := 2; matrix01_ld := '1'; matrix01_c := 2; matrix02_ld := '1'; matrix02_c := 2;
                                       matrix10_ld := '1'; matrix10_c := 2; matrix11_ld := '1'; matrix11_c := 2; matrix12_ld := '1'; matrix12_c := 2;
                                       matrix20_ld := '1'; matrix20_c := 2; matrix21_ld := '1'; matrix21_c := 2; matrix22_ld := '1'; matrix22_c := 2;
                        when 16#1E# => state <= CALC_NCS;
                                       translate0_ld := '1'; translate0_c := 1; translate1_ld := '1'; translate1_c := 1; translate2_ld := '1'; translate2_c := 1;
                        when 16#20# => state <= CALC_NCT;
                                       translate0_ld := '1'; translate0_c := 1; translate1_ld := '1'; translate1_c := 1; translate2_ld := '1'; translate2_c := 1;
                        when 16#28# => state <= CALC_SQR;
                        when 16#29# => state <= CALC_DPCL;
                                       translate0_ld := '1'; translate0_c := 2; translate1_ld := '1'; translate1_c := 2; translate2_ld := '1'; translate2_c := 2;
                        when 16#2A# => state <= CALC_DPCT; calcColor <= REG_RGB0(23 downto 0);
                                       translate0_ld := '1'; translate0_c := 2; translate1_ld := '1'; translate1_c := 2; translate2_ld := '1'; translate2_c := 2;
                        when 16#2D# => state <= CALC_AVSZ3;
                        when 16#2E# => state <= CALC_AVSZ4;
                        when 16#30# => state <= CALC_RTPT;
                                       translate0_ld := '1'; translate0_c := 0; translate1_ld := '1'; translate1_c := 0; translate2_ld := '1'; translate2_c := 0;
                                       matrix00_ld := '1'; matrix00_c := 0; matrix01_ld := '1'; matrix01_c := 0; matrix02_ld := '1'; matrix02_c := 0;
                                       matrix10_ld := '1'; matrix10_c := 0; matrix11_ld := '1'; matrix11_c := 0; matrix12_ld := '1'; matrix12_c := 0;
                                       matrix20_ld := '1'; matrix20_c := 0; matrix21_ld := '1'; matrix21_c := 0; matrix22_ld := '1'; matrix22_c := 0;
                                       vector0_ld := '1'; vector0_c := 0; vector1_ld := '1'; vector1_c := 0; vector2_ld := '1'; vector2_c := 0;
                        when 16#3D# => state <= CALC_GPF;
                        when 16#3E# => state <= CALC_GPL;
                        when 16#3F# => state <= CALC_NCCT;
                                       translate0_ld := '1'; translate0_c := 1; translate1_ld := '1'; translate1_c := 1; translate2_ld := '1'; translate2_c := 1;
                        when others => gte_busy <= '0';
                     end case;
                     
                     debugCnt <= debugCnt + 1;
                     if (debugCnt = 0) then
                        debug_firstGTE <= '1';
                     end if;
                     
                  elsif (clk2xIndex = '0') then
                     gte_busy <= '0';
                  end if;
                  
               when CALC_RTPS =>
                  case (calcStep) is
                     --                     mul1                        mul2                  add                           sub  swap    svSh  useIR    IRs    IRsF        satIR     satIRF  uRes trigger
                     when 0 => mac1_mode := 1; mac1_ca := 0; mac1_cb := 0; mac1_cadd := 0; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac2_mode := 1; mac2_ca := 0; mac2_cb := 0; mac2_cadd := 0; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac3_mode := 1; mac3_ca := 0; mac3_cb := 0; mac3_cadd := 0; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1');

                     when 1 => mac1_mode := 1; mac1_ca := 1; mac1_cb := 1; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1'); 
                               mac2_mode := 1; mac2_ca := 1; mac2_cb := 1; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1'); 
                               mac3_mode := 1; mac3_ca := 1; mac3_cb := 1; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1');
                                                                                                                            
                     when 2 => mac1_mode := 1; mac1_ca := 2; mac1_cb := 2; mac1_cadd := 1; mac1_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1'); 
                               mac2_mode := 1; mac2_ca := 2; mac2_cb := 2; mac2_cadd := 1; mac2_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1'); 
                               mac3_mode := 1; mac3_ca := 2; mac3_cb := 2; mac3_cadd := 1; mac3_fl := ('0', '0', cmdShift, '1', cmdShift, '1', cmdsatIR, '0', '1', '1');

                     when 3 => pushSZandDivide <= '1';

                              --             mul1                       mul2                    add         sub  swap useIR IRs cOvf uRes trigger
                     when 12 => mac0_mode := 1; mac0_c1 := 0; mac0_c2 := 0; mac0_c3 := 0; mac0_fl := ('0', '0', '0', '0', '1', '0', '1'); 
                     when 13 => mac0_mode := 1; mac0_c1 := 1; mac0_c2 := 0; mac0_c3 := 1; mac0_fl := ('0', '0', '0', '0', '1', '0', '1'); 
                     when 14 => pushSXY <= '1';
                     when 15 => mac0_mode := 1; mac0_c1 := 2; mac0_c2 := 0; mac0_c3 := 2; mac0_fl := ('0', '0', '1', '1', '1', '0', '1');
                               
                     when 17 => if (turbomode = '1') then state <= IDLE; end if;
                     when others => null;
                  end case;
                  
               when CALC_RTPT =>
                  case (calcStep) is
                     --                     mul1                        mul2                  add                           sub  swap    svSh  useIR    IRs    IRsF        satIR     satIRF  uRes trigger
                              -- first round
                     when 0 => mac1_mode := 1; mac1_ca := 0; mac1_cb := 0; mac1_cadd := 0; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac2_mode := 1; mac2_ca := 0; mac2_cb := 0; mac2_cadd := 0; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac3_mode := 1; mac3_ca := 0; mac3_cb := 0; mac3_cadd := 0; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1');                           
                               
                     when 1 => mac1_mode := 1; mac1_ca := 1; mac1_cb := 1; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1'); 
                               mac2_mode := 1; mac2_ca := 1; mac2_cb := 1; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1'); 
                               mac3_mode := 1; mac3_ca := 1; mac3_cb := 1; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1');
                                                                                                                            
                     when 2 => mac1_mode := 1; mac1_ca := 2; mac1_cb := 2; mac1_cadd := 1; mac1_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1'); 
                               mac2_mode := 1; mac2_ca := 2; mac2_cb := 2; mac2_cadd := 1; mac2_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1'); 
                               mac3_mode := 1; mac3_ca := 2; mac3_cb := 2; mac3_cadd := 1; mac3_fl := ('0', '0', cmdShift, '1', cmdShift, '1', cmdsatIR, '0', '1', '1');
                               vector0_ld := '1'; vector0_c := 1; vector1_ld := '1'; vector1_c := 1; vector2_ld := '1'; vector2_c := 1;

                     when 3 => pushSZandDivide <= '1';
                               -- second round
                               mac1_mode := 1; mac1_ca := 0; mac1_cb := 0; mac1_cadd := 0; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac2_mode := 1; mac2_ca := 0; mac2_cb := 0; mac2_cadd := 0; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac3_mode := 1; mac3_ca := 0; mac3_cb := 0; mac3_cadd := 0; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1');
                     
                     when 4 => mac1_mode := 1; mac1_ca := 1; mac1_cb := 1; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1'); 
                               mac2_mode := 1; mac2_ca := 1; mac2_cb := 1; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1'); 
                               mac3_mode := 1; mac3_ca := 1; mac3_cb := 1; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1');
                                                                                                                            
                     when 5 => mac1_mode := 1; mac1_ca := 2; mac1_cb := 2; mac1_cadd := 1; mac1_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1'); 
                               mac2_mode := 1; mac2_ca := 2; mac2_cb := 2; mac2_cadd := 1; mac2_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1'); 
                               mac3_mode := 1; mac3_ca := 2; mac3_cb := 2; mac3_cadd := 1; mac3_fl := ('0', '0', cmdShift, '1', cmdShift, '1', cmdsatIR, '0', '1', '1');
                               vector0_ld := '1'; vector0_c := 2; vector1_ld := '1'; vector1_c := 2; vector2_ld := '1'; vector2_c := 2;
                     when 6 => pushSZandDivide <= '1'; IR1aspect_1 <= IR1aspect; REG_IR2_1 <= REG_IR2;
                               -- third round
                               mac1_mode := 1; mac1_ca := 0; mac1_cb := 0; mac1_cadd := 0; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac2_mode := 1; mac2_ca := 0; mac2_cb := 0; mac2_cadd := 0; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac3_mode := 1; mac3_ca := 0; mac3_cb := 0; mac3_cadd := 0; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1');
                     
                     when 7 => mac1_mode := 1; mac1_ca := 1; mac1_cb := 1; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1'); 
                               mac2_mode := 1; mac2_ca := 1; mac2_cb := 1; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1'); 
                               mac3_mode := 1; mac3_ca := 1; mac3_cb := 1; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1');
                                                                                                                            
                     when 8 => mac1_mode := 1; mac1_ca := 2; mac1_cb := 2; mac1_cadd := 1; mac1_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1'); 
                               mac2_mode := 1; mac2_ca := 2; mac2_cb := 2; mac2_cadd := 1; mac2_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1'); 
                               mac3_mode := 1; mac3_ca := 2; mac3_cb := 2; mac3_cadd := 1; mac3_fl := ('0', '0', cmdShift, '1', cmdShift, '1', cmdsatIR, '0', '1', '1');
                     when 9 => pushSZandDivide <= '1'; IR1aspect_2 <= IR1aspect; REG_IR2_2 <= REG_IR2;

                              --             mul1                       mul2                    add         sub  swap useIR IRs cOvf uRes trigger
                              -- first round
                     when 12 => mac0_mode := 1; mac0_c1 := 3; mac0_c2 := 0; mac0_c3 := 0; mac0_fl := ('0', '0', '0', '0', '1', '0', '1'); 
                     when 13 => mac0_mode := 1; mac0_c1 := 4; mac0_c2 := 0; mac0_c3 := 1; mac0_fl := ('0', '0', '0', '0', '1', '0', '1'); 
                     when 14 => pushSXY <= '1';
                     
                              -- second round
                     when 15 => mac0_mode := 1; mac0_c1 := 5; mac0_c2 := 0; mac0_c3 := 0; mac0_fl := ('0', '0', '0', '0', '1', '0', '1'); 
                     when 16 => mac0_mode := 1; mac0_c1 := 6; mac0_c2 := 0; mac0_c3 := 1; mac0_fl := ('0', '0', '0', '0', '1', '0', '1'); 
                     when 17 => pushSXY <= '1';
                     
                              -- third round
                     when 18 => mac0_mode := 1; mac0_c1 := 0; mac0_c2 := 0; mac0_c3 := 0; mac0_fl := ('0', '0', '0', '0', '1', '0', '1'); 
                     when 19 => mac0_mode := 1; mac0_c1 := 1; mac0_c2 := 0; mac0_c3 := 1; mac0_fl := ('0', '0', '0', '0', '1', '0', '1'); 
                     when 20 => pushSXY <= '1';
                     
                     -- only for third round
                     when 21 =>  mac0_mode := 1; mac0_c1 := 2; mac0_c2 := 0; mac0_c3 := 2; mac0_fl := ('0', '0', '1', '1', '1', '0', '1');
                               
                     when 23 => if (turbomode = '1') then state <= IDLE; end if;
                     when others => null;
                  end case;
               
               when CALC_NCLIP =>
                  case (calcStep) is
                     --                                  mul1              mul2           add     sub  swap useIR IRs cOvf uRes trigger
                     when 0  => mac0_mode := 1; mac0_c1 := 7; mac0_c2 := 1; mac0_c3 := 3; mac0_fl := ('0', '0', '0', '0', '0', '0', '1'); 
                     when 1  => mac0_mode := 1; mac0_c1 := 8; mac0_c2 := 2; mac0_c3 := 3; mac0_fl := ('0', '0', '0', '0', '0', '1', '1'); 
                     when 2  => mac0_mode := 1; mac0_c1 := 9; mac0_c2 := 3; mac0_c3 := 3; mac0_fl := ('0', '0', '0', '0', '0', '1', '1'); 
                     when 3  => mac0_mode := 1; mac0_c1 := 7; mac0_c2 := 2; mac0_c3 := 3; mac0_fl := ('1', '0', '0', '0', '0', '1', '1'); 
                     when 4  => mac0_mode := 1; mac0_c1 := 8; mac0_c2 := 3; mac0_c3 := 3; mac0_fl := ('1', '0', '0', '0', '0', '1', '1'); 
                     when 5  => mac0_mode := 1; mac0_c1 := 9; mac0_c2 := 1; mac0_c3 := 3; mac0_fl := ('1', '0', '0', '0', '1', '1', '1'); 
                     when 7  => if (turbomode = '1') then state <= IDLE; end if;
                     when others => null;
                  end case;
                  
               when CALC_OP =>
                  case (calcStep) is
                     --                     mul1                        mul2                 add        sub  swap    svSh  useIR    IRs    IRsF        satIR     satIRF  uRes trigger
                     when 0 => mac1_mode := 1; mac1_ca := 3; mac1_cb := 3; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac2_mode := 1; mac2_ca := 3; mac2_cb := 3; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac3_mode := 1; mac3_ca := 3; mac3_cb := 3; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1');  
                                                                                                              
                     when 1 => mac1_mode := 1; mac1_ca := 4; mac1_cb := 4; mac1_cadd := 1; mac1_fl := ('1', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1'); 
                               mac2_mode := 1; mac2_ca := 4; mac2_cb := 4; mac2_cadd := 1; mac2_fl := ('1', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1'); 
                               mac3_mode := 1; mac3_ca := 4; mac3_cb := 4; mac3_cadd := 1; mac3_fl := ('1', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1');
                     
                     when 3 => if (turbomode = '1') then state <= IDLE; end if;
                     when others => null;
                  end case;
                  
               when CALC_DPCS | CALC_DPCT =>
                  case (calcStep) is
                     --                     mul1                                            mul2                    add        sub  swap    svSh  useIR    IRs    IRsF        satIR     satIRF  uRes trigger
                     when 0 => mac1_mode := 2; mac1_cv := 0; mac1_csh := 0; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac2_mode := 2; mac2_cv := 0; mac2_csh := 0; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac3_mode := 2; mac3_cv := 0; mac3_csh := 0; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1');  
                                                                                                              
                     when 1 => mac1_mode := 2; mac1_cv := 1; mac1_csh := 1; mac1_cadd := 1; mac1_fl := ('1', '1', cmdShift, '1', cmdShift, cmdShift, '0', '0', '1', '1'); 
                               mac2_mode := 2; mac2_cv := 1; mac2_csh := 1; mac2_cadd := 1; mac2_fl := ('1', '1', cmdShift, '1', cmdShift, cmdShift, '0', '0', '1', '1'); 
                               mac3_mode := 2; mac3_cv := 1; mac3_csh := 1; mac3_cadd := 1; mac3_fl := ('1', '1', cmdShift, '1', cmdShift, cmdShift, '0', '0', '1', '1');
                     
                     when 4 => mac1_mode := 1; mac1_ca := 5; mac1_cb := 5; mac1_cadd := 2; mac1_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '0', '1'); 
                               mac2_mode := 1; mac2_ca := 5; mac2_cb := 5; mac2_cadd := 2; mac2_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '0', '1'); 
                               mac3_mode := 1; mac3_ca := 5; mac3_cb := 5; mac3_cadd := 2; mac3_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '0', '1');
                     
                     when 5 => pushRGBfromMAC <= '1';
                    
                     when 8 => 
                        if (state = CALC_DPCS or batchCount = 2) then
                           if (turbomode = '1') then
                              state <= IDLE;
                           end if;
                        else
                           calcStep   <= 0;
                           batchCount <= batchCount + 1;
                           calcColor  <= REG_RGB0(23 downto 0);
                        end if;
                        
                     when others => null;
                  end case;               
                  
               when CALC_INTPL =>
                  case (calcStep) is
                     --                     mul1                    mul2                    add        sub  swap    svSh  useIR    IRs    IRsF        satIR     satIRF  uRes trigger
                     when 0 => mac1_mode := 2; mac1_cv := 2; mac1_csh := 1; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac2_mode := 2; mac2_cv := 2; mac2_csh := 1; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac3_mode := 2; mac3_cv := 2; mac3_csh := 1; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1');  
                                                                                                              
                     when 1 => mac1_mode := 2; mac1_cv := 1; mac1_csh := 1; mac1_cadd := 1; mac1_fl := ('1', '1', cmdShift, '1', cmdShift, cmdShift, '0', '0', '1', '1'); 
                               mac2_mode := 2; mac2_cv := 1; mac2_csh := 1; mac2_cadd := 1; mac2_fl := ('1', '1', cmdShift, '1', cmdShift, cmdShift, '0', '0', '1', '1'); 
                               mac3_mode := 2; mac3_cv := 1; mac3_csh := 1; mac3_cadd := 1; mac3_fl := ('1', '1', cmdShift, '1', cmdShift, cmdShift, '0', '0', '1', '1');
                     
                     when 4 => mac1_mode := 1; mac1_ca := 5; mac1_cb := 5; mac1_cadd := 2; mac1_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '0', '1'); 
                               mac2_mode := 1; mac2_ca := 5; mac2_cb := 5; mac2_cadd := 2; mac2_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '0', '1'); 
                               mac3_mode := 1; mac3_ca := 5; mac3_cb := 5; mac3_cadd := 2; mac3_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '0', '1');
                     
                     when 5 => pushRGBfromMAC <= '1';
                    
                     when 8 => if (turbomode = '1') then state <= IDLE; end if;
                     when others => null;
                  end case;
                  
               when CALC_MVMVA =>
                  case (calcStep) is
                     when 0 => null;
                     --                     mul1                    mul2                     add        sub  swap    svSh  useIR    IRs    IRsF        satIR     satIRF  uRes trigger
                     when 1 => mac1_mode := 2; mac1_cv := 3; mac1_csh := 1; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac2_mode := 2; mac2_cv := 3; mac2_csh := 1; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac3_mode := 2; mac3_cv := 3; mac3_csh := 1; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1');  
                                                                 
                     when 2 =>                                   
                        if (cmdTV = "10") then -- buggy               
                               mac1_mode := 1; mac1_ca := 0; mac1_cb := 0; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '1', cmdShift, cmdShift, '0', '0', '1', '1'); 
                               mac2_mode := 1; mac2_ca := 0; mac2_cb := 0; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '1', cmdShift, cmdShift, '0', '0', '1', '1'); 
                               mac3_mode := 1; mac3_ca := 0; mac3_cb := 0; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '1', cmdShift, cmdShift, '0', '0', '1', '1');
                        else
                               mac1_mode := 1; mac1_ca := 0; mac1_cb := 0; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1'); 
                               mac2_mode := 1; mac2_ca := 0; mac2_cb := 0; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1'); 
                               mac3_mode := 1; mac3_ca := 0; mac3_cb := 0; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1');
                        end if;
                               
                     when 3 => 
                        if (cmdTV = "10") then -- buggy
                               mac1_mode := 1; mac1_ca := 1; mac1_cb := 1; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac2_mode := 1; mac2_ca := 1; mac2_cb := 1; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac3_mode := 1; mac3_ca := 1; mac3_cb := 1; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1');
                        else                                     
                               mac1_mode := 1; mac1_ca := 1; mac1_cb := 1; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1'); 
                               mac2_mode := 1; mac2_ca := 1; mac2_cb := 1; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1'); 
                               mac3_mode := 1; mac3_ca := 1; mac3_cb := 1; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1');
                        end if;                                  
                                                                 
                     when 4 => mac1_mode := 1; mac1_ca := 2; mac1_cb := 2; mac1_cadd := 1; mac1_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1');
                               mac2_mode := 1; mac2_ca := 2; mac2_cb := 2; mac2_cadd := 1; mac2_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1');
                               mac3_mode := 1; mac3_ca := 2; mac3_cb := 2; mac3_cadd := 1; mac3_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1');
                    
                     when 6 => if (turbomode = '1') then state <= IDLE; end if;
                     when others => null;
                  end case;
               
               when CALC_NCDS | CALC_NCDT =>
                  case (calcStep) is
                     when 0 =>
                        matrix00_ld := '1'; matrix00_c := 1; matrix01_ld := '1'; matrix01_c := 1; matrix02_ld := '1'; matrix02_c := 1;
                        matrix10_ld := '1'; matrix10_c := 1; matrix11_ld := '1'; matrix11_c := 1; matrix12_ld := '1'; matrix12_c := 1;
                        matrix20_ld := '1'; matrix20_c := 1; matrix21_ld := '1'; matrix21_c := 1; matrix22_ld := '1'; matrix22_c := 1;
                        case (batchCount) is
                           when 0 => vector0_ld := '1'; vector0_c := 0; vector1_ld := '1'; vector1_c := 0; vector2_ld := '1'; vector2_c := 0;
                           when 1 => vector0_ld := '1'; vector0_c := 1; vector1_ld := '1'; vector1_c := 1; vector2_ld := '1'; vector2_c := 1;
                           when 2 => vector0_ld := '1'; vector0_c := 2; vector1_ld := '1'; vector1_c := 2; vector2_ld := '1'; vector2_c := 2;
                        end case;

                     --                     mul1                       mul2                                            add     sub  swap    svSh  useIR    IRs    IRsF        satIR     satIRF  uRes trigger
                     when 1 => mac1_mode := 1; mac1_ca := 0; mac1_cb := 0; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac2_mode := 1; mac2_ca := 0; mac2_cb := 0; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac3_mode := 1; mac3_ca := 0; mac3_cb := 0; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                                                                                                             
                     when 2 => mac1_mode := 1; mac1_ca := 1; mac1_cb := 1; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1');
                               mac2_mode := 1; mac2_ca := 1; mac2_cb := 1; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1');
                               mac3_mode := 1; mac3_ca := 1; mac3_cb := 1; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1');
                                                                                                             
                     when 3 => mac1_mode := 1; mac1_ca := 2; mac1_cb := 2; mac1_cadd := 1; mac1_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1'); 
                               mac2_mode := 1; mac2_ca := 2; mac2_cb := 2; mac2_cadd := 1; mac2_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1'); 
                               mac3_mode := 1; mac3_ca := 2; mac3_cb := 2; mac3_cadd := 1; mac3_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1');
                               translate0_ld := '1'; translate0_c := 1; translate1_ld := '1'; translate1_c := 1; translate2_ld := '1'; translate2_c := 1;  -- BK for step 4
                                                                                                             
                     --  mat mul with color matrix                                                           
                     when 4 => mac1_mode := 2; mac1_cv := 4; mac1_csh := 1; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac2_mode := 2; mac2_cv := 4; mac2_csh := 1; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac3_mode := 2; mac3_cv := 4; mac3_csh := 1; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               matrix00_ld := '1'; matrix00_c := 2; matrix01_ld := '1'; matrix01_c := 2; matrix02_ld := '1'; matrix02_c := 2;
                               matrix10_ld := '1'; matrix10_c := 2; matrix11_ld := '1'; matrix11_c := 2; matrix12_ld := '1'; matrix12_c := 2;
                               matrix20_ld := '1'; matrix20_c := 2; matrix21_ld := '1'; matrix21_c := 2; matrix22_ld := '1'; matrix22_c := 2;
                                                                                                             
                     when 6 => mac1_mode := 1; mac1_ca := 0; mac1_cb := 6; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1'); 
                               mac2_mode := 1; mac2_ca := 0; mac2_cb := 3; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1'); 
                               mac3_mode := 1; mac3_ca := 0; mac3_cb := 4; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1'); 
                                                                                                             
                     when 7 => mac1_mode := 1; mac1_ca := 1; mac1_cb := 4; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1');
                               mac2_mode := 1; mac2_ca := 1; mac2_cb := 6; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1');
                               mac3_mode := 1; mac3_ca := 1; mac3_cb := 3; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1');
                                                                                                             
                     when 8 => mac1_mode := 1; mac1_ca := 2; mac1_cb := 3; mac1_cadd := 1; mac1_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1'); 
                               mac2_mode := 1; mac2_ca := 2; mac2_cb := 4; mac2_cadd := 1; mac2_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1'); 
                               mac3_mode := 1; mac3_ca := 2; mac3_cb := 6; mac3_cadd := 1; mac3_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1');

                     -- prepare IR for InterpolateColor
                     when 11 => mac1_mode := 1; mac1_ca := 5; mac1_cb := 7; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                                mac2_mode := 1; mac2_ca := 5; mac2_cb := 7; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                                mac3_mode := 1; mac3_ca := 5; mac3_cb := 7; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 

                     when 13 => mac1_mode := 2; mac1_cv := 5; mac1_csh := 2; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                                mac2_mode := 2; mac2_cv := 5; mac2_csh := 2; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                                mac3_mode := 2; mac3_cv := 5; mac3_csh := 2; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1');
                                translate0_ld := '1'; translate0_c := 2; translate1_ld := '1'; translate1_c := 2; translate2_ld := '1'; translate2_c := 2;  -- FC for step 14

                     -- InterpolateColor
                     when 14 => mac1_mode := 2; mac1_cv := 1; mac1_csh := 1; mac1_cadd := 1; mac1_fl := ('1', '1', cmdShift, '1', cmdShift, cmdShift, '0', '0', '1', '1'); 
                                mac2_mode := 2; mac2_cv := 1; mac2_csh := 1; mac2_cadd := 1; mac2_fl := ('1', '1', cmdShift, '1', cmdShift, cmdShift, '0', '0', '1', '1'); 
                                mac3_mode := 2; mac3_cv := 1; mac3_csh := 1; mac3_cadd := 1; mac3_fl := ('1', '1', cmdShift, '1', cmdShift, cmdShift, '0', '0', '1', '1');

                     when 17 => mac1_mode := 1; mac1_ca := 5; mac1_cb := 5; mac1_cadd := 2; mac1_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '0', '1'); 
                                mac2_mode := 1; mac2_ca := 5; mac2_cb := 5; mac2_cadd := 2; mac2_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '0', '1'); 
                                mac3_mode := 1; mac3_ca := 5; mac3_cb := 5; mac3_cadd := 2; mac3_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '0', '1');

                     when 18 => pushRGBfromMAC <= '1';       
                     
                     when 21 => 
                        if (state = CALC_NCDS or batchCount = 2) then
                           if (turbomode = '1') then 
                              state <= IDLE; 
                           end if;
                        else
                           calcStep   <= 0;
                           batchCount <= batchCount + 1;
                        end if;
                     
                     when others => null;
                  end case;        

            when CALC_CDP =>
                  case (calcStep) is
                     --                     mul1                       mul2                                            add     sub  swap    svSh  useIR    IRs    IRsF        satIR     satIRF  uRes trigger                                                                          
                     --  mat mul with color matrix                                                           
                     when 0 => mac1_mode := 2; mac1_cv := 4; mac1_csh := 1; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac2_mode := 2; mac2_cv := 4; mac2_csh := 1; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac3_mode := 2; mac3_cv := 4; mac3_csh := 1; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                                                                                                             
                     when 1 => mac1_mode := 1; mac1_ca := 0; mac1_cb := 6; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1'); 
                               mac2_mode := 1; mac2_ca := 0; mac2_cb := 3; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1'); 
                               mac3_mode := 1; mac3_ca := 0; mac3_cb := 4; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1'); 
                                                                                                             
                     when 2 => mac1_mode := 1; mac1_ca := 1; mac1_cb := 4; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1');
                               mac2_mode := 1; mac2_ca := 1; mac2_cb := 6; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1');
                               mac3_mode := 1; mac3_ca := 1; mac3_cb := 3; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1');
                                                                                                             
                     when 3 => mac1_mode := 1; mac1_ca := 2; mac1_cb := 3; mac1_cadd := 1; mac1_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1'); 
                               mac2_mode := 1; mac2_ca := 2; mac2_cb := 4; mac2_cadd := 1; mac2_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1'); 
                               mac3_mode := 1; mac3_ca := 2; mac3_cb := 6; mac3_cadd := 1; mac3_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1');

                     -- prepare IR for InterpolateColor
                     when 6 => mac1_mode := 1; mac1_ca := 5; mac1_cb := 7; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac2_mode := 1; mac2_ca := 5; mac2_cb := 7; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac3_mode := 1; mac3_ca := 5; mac3_cb := 7; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 

                     when 8 =>  mac1_mode := 2; mac1_cv := 5; mac1_csh := 2; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                                mac2_mode := 2; mac2_cv := 5; mac2_csh := 2; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                                mac3_mode := 2; mac3_cv := 5; mac3_csh := 2; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1');
                                translate0_ld := '1'; translate0_c := 2; translate1_ld := '1'; translate1_c := 2; translate2_ld := '1'; translate2_c := 2;  -- FC for step 9

                     -- InterpolateColor
                     when 9 =>  mac1_mode := 2; mac1_cv := 1; mac1_csh := 1; mac1_cadd := 1; mac1_fl := ('1', '1', cmdShift, '1', cmdShift, cmdShift, '0', '0', '1', '1'); 
                                mac2_mode := 2; mac2_cv := 1; mac2_csh := 1; mac2_cadd := 1; mac2_fl := ('1', '1', cmdShift, '1', cmdShift, cmdShift, '0', '0', '1', '1'); 
                                mac3_mode := 2; mac3_cv := 1; mac3_csh := 1; mac3_cadd := 1; mac3_fl := ('1', '1', cmdShift, '1', cmdShift, cmdShift, '0', '0', '1', '1');

                     when 12 => mac1_mode := 1; mac1_ca := 5; mac1_cb := 5; mac1_cadd := 2; mac1_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '0', '1'); 
                                mac2_mode := 1; mac2_ca := 5; mac2_cb := 5; mac2_cadd := 2; mac2_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '0', '1'); 
                                mac3_mode := 1; mac3_ca := 5; mac3_cb := 5; mac3_cadd := 2; mac3_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '0', '1');

                     when 13 => pushRGBfromMAC <= '1';
                               
                     when 16 => if (turbomode = '1') then state <= IDLE; end if;
                     when others => null;
                  end case;   

            when CALC_NCCS | CALC_NCCT =>
                  case (calcStep) is
                     when 0 =>
                        matrix00_ld := '1'; matrix00_c := 1; matrix01_ld := '1'; matrix01_c := 1; matrix02_ld := '1'; matrix02_c := 1;
                        matrix10_ld := '1'; matrix10_c := 1; matrix11_ld := '1'; matrix11_c := 1; matrix12_ld := '1'; matrix12_c := 1;
                        matrix20_ld := '1'; matrix20_c := 1; matrix21_ld := '1'; matrix21_c := 1; matrix22_ld := '1'; matrix22_c := 1;
                        case (batchCount) is
                           when 0 => vector0_ld := '1'; vector0_c := 0; vector1_ld := '1'; vector1_c := 0; vector2_ld := '1'; vector2_c := 0;
                           when 1 => vector0_ld := '1'; vector0_c := 1; vector1_ld := '1'; vector1_c := 1; vector2_ld := '1'; vector2_c := 1;
                           when 2 => vector0_ld := '1'; vector0_c := 2; vector1_ld := '1'; vector1_c := 2; vector2_ld := '1'; vector2_c := 2;
                        end case;

                     --                     mul1                       mul2                                            add     sub  swap    svSh  useIR    IRs    IRsF        satIR     satIRF  uRes trigger
                     when 1 => mac1_mode := 1; mac1_ca := 0; mac1_cb := 0; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac2_mode := 1; mac2_ca := 0; mac2_cb := 0; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac3_mode := 1; mac3_ca := 0; mac3_cb := 0; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                                                                                                             
                     when 2 => mac1_mode := 1; mac1_ca := 1; mac1_cb := 1; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1');
                               mac2_mode := 1; mac2_ca := 1; mac2_cb := 1; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1');
                               mac3_mode := 1; mac3_ca := 1; mac3_cb := 1; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1');
                                                                                                             
                     when 3 => mac1_mode := 1; mac1_ca := 2; mac1_cb := 2; mac1_cadd := 1; mac1_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1'); 
                               mac2_mode := 1; mac2_ca := 2; mac2_cb := 2; mac2_cadd := 1; mac2_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1'); 
                               mac3_mode := 1; mac3_ca := 2; mac3_cb := 2; mac3_cadd := 1; mac3_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1');
                                                                                                             
                     --  mat mul with color matrix                                                           
                     when 4 => mac1_mode := 2; mac1_cv := 4; mac1_csh := 1; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac2_mode := 2; mac2_cv := 4; mac2_csh := 1; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac3_mode := 2; mac3_cv := 4; mac3_csh := 1; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               matrix00_ld := '1'; matrix00_c := 2; matrix01_ld := '1'; matrix01_c := 2; matrix02_ld := '1'; matrix02_c := 2;
                               matrix10_ld := '1'; matrix10_c := 2; matrix11_ld := '1'; matrix11_c := 2; matrix12_ld := '1'; matrix12_c := 2;
                               matrix20_ld := '1'; matrix20_c := 2; matrix21_ld := '1'; matrix21_c := 2; matrix22_ld := '1'; matrix22_c := 2;
                                                                                                             
                     when 6 => mac1_mode := 1; mac1_ca := 0; mac1_cb := 6; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1'); 
                               mac2_mode := 1; mac2_ca := 0; mac2_cb := 3; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1'); 
                               mac3_mode := 1; mac3_ca := 0; mac3_cb := 4; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1'); 
                                                                                                             
                     when 7 => mac1_mode := 1; mac1_ca := 1; mac1_cb := 4; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1');
                               mac2_mode := 1; mac2_ca := 1; mac2_cb := 6; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1');
                               mac3_mode := 1; mac3_ca := 1; mac3_cb := 3; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1');
                                                                                                             
                     when 8 => mac1_mode := 1; mac1_ca := 2; mac1_cb := 3; mac1_cadd := 1; mac1_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1'); 
                               mac2_mode := 1; mac2_ca := 2; mac2_cb := 4; mac2_cadd := 1; mac2_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1'); 
                               mac3_mode := 1; mac3_ca := 2; mac3_cb := 6; mac3_cadd := 1; mac3_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1');

                     -- prepare IR for InterpolateColor
                     when 11 => mac1_mode := 1; mac1_ca := 5; mac1_cb := 7; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                                mac2_mode := 1; mac2_ca := 5; mac2_cb := 7; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                                mac3_mode := 1; mac3_ca := 5; mac3_cb := 7; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 

                     when 13 => mac1_mode := 2; mac1_cv := 5; mac1_csh := 2; mac1_cadd := 1; mac1_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '0', '1');
                                mac2_mode := 2; mac2_cv := 5; mac2_csh := 2; mac2_cadd := 1; mac2_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '0', '1');
                                mac3_mode := 2; mac3_cv := 5; mac3_csh := 2; mac3_cadd := 1; mac3_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '0', '1');

                     when 14 => pushRGBfromMAC <= '1';
                               
                     when 17 => 
                        if (state = CALC_NCCS or batchCount = 2) then
                           if (turbomode = '1') then 
                              state <= IDLE; 
                           end if;
                        else
                           calcStep   <= 0;
                           batchCount <= batchCount + 1;
                        end if;
                     
                     when others => null;
                  end case;  
                  
               when CALC_CC =>
                  case (calcStep) is
                     --                     mul1                       mul2                                            add     sub  swap    svSh  useIR    IRs    IRsF        satIR     satIRF  uRes trigger                                                                          
                     --  mat mul with color matrix                                                           
                     when 0 => mac1_mode := 2; mac1_cv := 4; mac1_csh := 1; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac2_mode := 2; mac2_cv := 4; mac2_csh := 1; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac3_mode := 2; mac3_cv := 4; mac3_csh := 1; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                                                                                                             
                     when 1 => mac1_mode := 1; mac1_ca := 0; mac1_cb := 6; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1'); 
                               mac2_mode := 1; mac2_ca := 0; mac2_cb := 3; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1'); 
                               mac3_mode := 1; mac3_ca := 0; mac3_cb := 4; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1'); 
                                                                                                             
                     when 2 => mac1_mode := 1; mac1_ca := 1; mac1_cb := 4; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1');
                               mac2_mode := 1; mac2_ca := 1; mac2_cb := 6; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1');
                               mac3_mode := 1; mac3_ca := 1; mac3_cb := 3; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1');
                                                                                                             
                     when 3 => mac1_mode := 1; mac1_ca := 2; mac1_cb := 3; mac1_cadd := 1; mac1_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1'); 
                               mac2_mode := 1; mac2_ca := 2; mac2_cb := 4; mac2_cadd := 1; mac2_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1'); 
                               mac3_mode := 1; mac3_ca := 2; mac3_cb := 6; mac3_cadd := 1; mac3_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1');

                     -- prepare IR for InterpolateColor
                     when 6 => mac1_mode := 1; mac1_ca := 5; mac1_cb := 7; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac2_mode := 1; mac2_ca := 5; mac2_cb := 7; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac3_mode := 1; mac3_ca := 5; mac3_cb := 7; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 

                     when 8 => mac1_mode := 2; mac1_cv := 5; mac1_csh := 2; mac1_cadd := 1; mac1_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '0', '1');
                               mac2_mode := 2; mac2_cv := 5; mac2_csh := 2; mac2_cadd := 1; mac2_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '0', '1');
                               mac3_mode := 2; mac3_cv := 5; mac3_csh := 2; mac3_cadd := 1; mac3_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '0', '1');

                     when 9 => pushRGBfromMAC <= '1';
                               
                     when 12 => if (turbomode = '1') then state <= IDLE; end if;
                     when others => null;
                  end case; 

               when CALC_NCS | CALC_NCT =>
                  case (calcStep) is
                     when 0 =>
                        matrix00_ld := '1'; matrix00_c := 1; matrix01_ld := '1'; matrix01_c := 1; matrix02_ld := '1'; matrix02_c := 1;
                        matrix10_ld := '1'; matrix10_c := 1; matrix11_ld := '1'; matrix11_c := 1; matrix12_ld := '1'; matrix12_c := 1;
                        matrix20_ld := '1'; matrix20_c := 1; matrix21_ld := '1'; matrix21_c := 1; matrix22_ld := '1'; matrix22_c := 1;
                        case (batchCount) is
                           when 0 => vector0_ld := '1'; vector0_c := 0; vector1_ld := '1'; vector1_c := 0; vector2_ld := '1'; vector2_c := 0;
                           when 1 => vector0_ld := '1'; vector0_c := 1; vector1_ld := '1'; vector1_c := 1; vector2_ld := '1'; vector2_c := 1;
                           when 2 => vector0_ld := '1'; vector0_c := 2; vector1_ld := '1'; vector1_c := 2; vector2_ld := '1'; vector2_c := 2;
                        end case;

                     --                     mul1                       mul2                                            add     sub  swap    svSh  useIR    IRs    IRsF        satIR     satIRF  uRes trigger
                     when 1 => mac1_mode := 1; mac1_ca := 0; mac1_cb := 0; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac2_mode := 1; mac2_ca := 0; mac2_cb := 0; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac3_mode := 1; mac3_ca := 0; mac3_cb := 0; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                                                                                                             
                     when 2 => mac1_mode := 1; mac1_ca := 1; mac1_cb := 1; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1');
                               mac2_mode := 1; mac2_ca := 1; mac2_cb := 1; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1');
                               mac3_mode := 1; mac3_ca := 1; mac3_cb := 1; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1');
                                                                                                             
                     when 3 => mac1_mode := 1; mac1_ca := 2; mac1_cb := 2; mac1_cadd := 1; mac1_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1'); 
                               mac2_mode := 1; mac2_ca := 2; mac2_cb := 2; mac2_cadd := 1; mac2_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1'); 
                               mac3_mode := 1; mac3_ca := 2; mac3_cb := 2; mac3_cadd := 1; mac3_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1');
                                                                                                             
                     --  mat mul with color matrix                                                           
                     when 4 => mac1_mode := 2; mac1_cv := 4; mac1_csh := 1; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac2_mode := 2; mac2_cv := 4; mac2_csh := 1; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac3_mode := 2; mac3_cv := 4; mac3_csh := 1; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               matrix00_ld := '1'; matrix00_c := 2; matrix01_ld := '1'; matrix01_c := 2; matrix02_ld := '1'; matrix02_c := 2;
                               matrix10_ld := '1'; matrix10_c := 2; matrix11_ld := '1'; matrix11_c := 2; matrix12_ld := '1'; matrix12_c := 2;
                               matrix20_ld := '1'; matrix20_c := 2; matrix21_ld := '1'; matrix21_c := 2; matrix22_ld := '1'; matrix22_c := 2;
                                                                                                             
                     when 6 => mac1_mode := 1; mac1_ca := 0; mac1_cb := 6; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1'); 
                               mac2_mode := 1; mac2_ca := 0; mac2_cb := 3; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1'); 
                               mac3_mode := 1; mac3_ca := 0; mac3_cb := 4; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1'); 
                                                                                                             
                     when 7 => mac1_mode := 1; mac1_ca := 1; mac1_cb := 4; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1');
                               mac2_mode := 1; mac2_ca := 1; mac2_cb := 6; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1');
                               mac3_mode := 1; mac3_ca := 1; mac3_cb := 3; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '1', '1');
                                                                                                             
                     when 8 => mac1_mode := 1; mac1_ca := 2; mac1_cb := 3; mac1_cadd := 1; mac1_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1'); 
                               mac2_mode := 1; mac2_ca := 2; mac2_cb := 4; mac2_cadd := 1; mac2_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1'); 
                               mac3_mode := 1; mac3_ca := 2; mac3_cb := 6; mac3_cadd := 1; mac3_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1');

                     when 9 => pushRGBfromMAC <= '1';
                               
                     when 12 => 
                        if (state = CALC_NCS or batchCount = 2) then
                           if (turbomode = '1') then 
                              state <= IDLE; 
                           end if;
                        else
                           calcStep   <= 0;
                           batchCount <= batchCount + 1;
                        end if;
                     when others => null;
                  end case;                  
                  
               when CALC_SQR =>
                  case (calcStep) is
                     --                     mul1                       mul2                    add     sub  swap    svSh  useIR    IRs    IRsF        satIR     satIRF  uRes trigger
                     when 0 => mac1_mode := 1; mac1_ca := 5; mac1_cb := 6; mac1_cadd := 1; mac1_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '0', '1'); 
                               mac2_mode := 1; mac2_ca := 5; mac2_cb := 6; mac2_cadd := 1; mac2_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '0', '1'); 
                               mac3_mode := 1; mac3_ca := 5; mac3_cb := 6; mac3_cadd := 1; mac3_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '0', '1'); 
                     when 2 => if (turbomode = '1') then state <= IDLE; end if;
                     when others => null;
                  end case;
                  
               when CALC_DPCL =>
                  case (calcStep) is
                     --                     mul1                       mul2                                            add     sub  swap    svSh  useIR    IRs    IRsF        satIR     satIRF  uRes trigger
                     -- prepare IR for InterpolateColor
                     when 0  => mac1_mode := 1; mac1_ca := 5; mac1_cb := 7; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                                mac2_mode := 1; mac2_ca := 5; mac2_cb := 7; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                                mac3_mode := 1; mac3_ca := 5; mac3_cb := 7; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 

                     when 2  => mac1_mode := 2; mac1_cv := 5; mac1_csh := 2; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                                mac2_mode := 2; mac2_cv := 5; mac2_csh := 2; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                                mac3_mode := 2; mac3_cv := 5; mac3_csh := 2; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1');

                     -- InterpolateColor
                     when 3  => mac1_mode := 2; mac1_cv := 1; mac1_csh := 1; mac1_cadd := 1; mac1_fl := ('1', '1', cmdShift, '1', cmdShift, cmdShift, '0', '0', '1', '1'); 
                                mac2_mode := 2; mac2_cv := 1; mac2_csh := 1; mac2_cadd := 1; mac2_fl := ('1', '1', cmdShift, '1', cmdShift, cmdShift, '0', '0', '1', '1'); 
                                mac3_mode := 2; mac3_cv := 1; mac3_csh := 1; mac3_cadd := 1; mac3_fl := ('1', '1', cmdShift, '1', cmdShift, cmdShift, '0', '0', '1', '1');

                     when 6  => mac1_mode := 1; mac1_ca := 5; mac1_cb := 5; mac1_cadd := 2; mac1_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '0', '1'); 
                                mac2_mode := 1; mac2_ca := 5; mac2_cb := 5; mac2_cadd := 2; mac2_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '0', '1'); 
                                mac3_mode := 1; mac3_ca := 5; mac3_cb := 5; mac3_cadd := 2; mac3_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '0', '1');

                     when 7  => pushRGBfromMAC <= '1';
                     when others => null;
                  end case;

               when CALC_AVSZ3 =>
                  case (calcStep) is
                     --                     mul1                            mul2            add     sub  swap useIR IRs cOvf uRes trigger
                     when 0 => mac0_mode := 1; mac0_c1 := 10; mac0_c2 := 4; mac0_c3 := 3; mac0_fl := ('0', '0', '0', '0', '1', '0', '1'); 
                     when 1 => mac0_mode := 1; mac0_c1 := 11; mac0_c2 := 4; mac0_c3 := 3; mac0_fl := ('0', '0', '0', '0', '1', '1', '1'); 
                     when 2 => mac0_mode := 1; mac0_c1 := 12; mac0_c2 := 4; mac0_c3 := 3; mac0_fl := ('0', '0', '0', '0', '1', '1', '1'); 
                     when 3 => setOTZ <= '1';
                     when others => null;
                  end case;                  
               
               when CALC_AVSZ4 =>
                  case (calcStep) is
                     --                     mul1                            mul2            add     sub  swap useIR IRs cOvf uRes trigger
                     when 0 => mac0_mode := 1; mac0_c1 := 13; mac0_c2 := 5; mac0_c3 := 3; mac0_fl := ('0', '0', '0', '0', '1', '0', '1'); 
                     when 1 => mac0_mode := 1; mac0_c1 := 10; mac0_c2 := 5; mac0_c3 := 3; mac0_fl := ('0', '0', '0', '0', '1', '1', '1'); 
                     when 2 => mac0_mode := 1; mac0_c1 := 11; mac0_c2 := 5; mac0_c3 := 3; mac0_fl := ('0', '0', '0', '0', '1', '1', '1'); 
                     when 3 => mac0_mode := 1; mac0_c1 := 12; mac0_c2 := 5; mac0_c3 := 3; mac0_fl := ('0', '0', '0', '0', '1', '1', '1'); 
                     when 4 => setOTZ <= '1';
                     when others => null;
                  end case;  
            
               when CALC_GPF =>
                  case (calcStep) is
                     --                    mul1                       mul2                  add        sub  swap    svSh  useIR    IRs    IRsF        satIR     satIRF  uRes trigger
                     when 0 => mac1_mode := 1; mac1_ca := 5; mac1_cb := 5; mac1_cadd := 1; mac1_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '0', '1'); 
                               mac2_mode := 1; mac2_ca := 5; mac2_cb := 5; mac2_cadd := 1; mac2_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '0', '1'); 
                               mac3_mode := 1; mac3_ca := 5; mac3_cb := 5; mac3_cadd := 1; mac3_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '0', '1');

                     when 1 => pushRGBfromMAC <= '1';
                     when others => null;
                  end case;
               
               when CALC_GPL =>
                  case (calcStep) is
                     when 0 =>
                        if (cmdShift = '1') then 
                           shiftcode <= SH12;
                        else
                           shiftcode <= SH0;
                        end if;
                     --                    mul1                      mul2                   add        sub  swap    svSh  useIR    IRs    IRsF        satIR     satIRF  uRes trigger
                     when 1 => mac1_mode := 2; mac1_cv := 6; mac1_csh := 3; mac1_cadd := 1; mac1_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac2_mode := 2; mac2_cv := 6; mac2_csh := 3; mac2_cadd := 1; mac2_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                               mac3_mode := 2; mac3_cv := 6; mac3_csh := 3; mac3_cadd := 1; mac3_fl := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '1'); 
                     
                     when 2 => mac1_mode := 1; mac1_ca := 5; mac1_cb := 5; mac1_cadd := 1; mac1_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1'); 
                               mac2_mode := 1; mac2_ca := 5; mac2_cb := 5; mac2_cadd := 1; mac2_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1'); 
                               mac3_mode := 1; mac3_ca := 5; mac3_cb := 5; mac3_cadd := 1; mac3_fl := ('0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR, '1', '1');

                     when 3 => pushRGBfromMAC <= '1';
                     when others => null;
                  end case;
            
            end case;
            
            if (state /= IDLE and calcStep = lastStep(state)) then
               state <= IDLE;
            end if;
            
            -- ofCode for the next step (see ofCode): H for the divides, then OFX / OFY / DQB for MAC0
            case (state) is
               when IDLE =>
                  if (gte_cmdEna = '1' and clk2xIndex = '1') then
                     case (to_integer(gte_cmdData(5 downto 0))) is
                        when 16#01# | 16#30# => ofCode <= "010";  -- RTPS / RTPT: H
                        when 16#2D#          => ofCode <= "101";  -- AVSZ3: ZSF3
                        when 16#2E#          => ofCode <= "110";  -- AVSZ4: ZSF4
                        when others          => null;
                     end case;
                  end if;
               when CALC_RTPS =>
                  case (calcStep) is
                     when 4      => ofCode <= "000";  -- OFX at 12 (H is read at 4)
                     when 12     => ofCode <= "001";  -- OFY at 13
                     when 13     => ofCode <= "100";  -- DQB at 15
                     when others => null;
                  end case;
               when CALC_RTPT =>
                  case (calcStep) is
                     when 10 | 13 | 16 => ofCode <= "000";  -- OFX at 12 / 15 / 18 (H is read at 4, 7, 10)
                     when 12 | 15 | 18 => ofCode <= "001";  -- OFY at 13 / 16 / 19
                     when 19           => ofCode <= "100";  -- DQB at 21
                     when others       => null;
                  end case;
               when others => null;
            end case;
         -- latch loads from the select codes (Pocket: compact multiplexers)
         if (matrix00_ld = '1') then
            matCode(0) <= std_logic_vector(to_unsigned(matrix00_c, 2));
            if (matrix00_c = 3) then matGarbage <= '1'; else matGarbage <= '0'; end if;   -- all nine are loaded together
            if (matrix00_c = 3) then matrix3_00 <= to_signed(0, 16) - signed((x"0" & REG_RGBC(7 downto 0) & x"0")); end if;
         end if;
         if (matrix01_ld = '1') then
            matCode(1) <= std_logic_vector(to_unsigned(matrix01_c, 2));
            if (matrix01_c = 3) then matrix3_01 <= signed(x"0" & REG_RGBC(7 downto 0) & x"0"); end if;
         end if;
         if (matrix02_ld = '1') then
            matCode(2) <= std_logic_vector(to_unsigned(matrix02_c, 2));
            if (matrix02_c = 3) then matCode(2) <= "00"; end if;   -- RT13 for rows 1 / 2 of the garbage matrix
            if (matrix02_c = 3) then matrix3_02 <= REG_IR0; end if;
         end if;
         if (matrix10_ld = '1') then matCode(3) <= std_logic_vector(to_unsigned(matrix10_c, 2)); end if;
         if (matrix11_ld = '1') then
            matCode(4) <= std_logic_vector(to_unsigned(matrix11_c, 2));
            if (matrix11_c = 3) then matCode(4) <= "00"; end if;   -- RT22 for row 2 of the garbage matrix
         end if;
         if (matrix12_ld = '1') then matCode(5) <= std_logic_vector(to_unsigned(matrix12_c, 2)); end if;
         if (matrix20_ld = '1') then matCode(6) <= std_logic_vector(to_unsigned(matrix20_c, 2)); end if;
         if (matrix21_ld = '1') then matCode(7) <= std_logic_vector(to_unsigned(matrix21_c, 2)); end if;
         if (matrix22_ld = '1') then matCode(8) <= std_logic_vector(to_unsigned(matrix22_c, 2)); end if;
         if (vector0_ld = '1') then
            case (vector0_c) is
               when 0 => vector0 <= REG_V0X;
               when 1 => vector0 <= REG_V1X;
               when 2 => vector0 <= REG_V2X;
               when 3 => vector0 <= REG_IR1;
               when others => null;
            end case;
         end if;
         if (vector1_ld = '1') then
            case (vector1_c) is
               when 0 => vector1 <= REG_V0Y;
               when 1 => vector1 <= REG_V1Y;
               when 2 => vector1 <= REG_V2Y;
               when 3 => vector1 <= REG_IR2;
               when others => null;
            end case;
         end if;
         if (vector2_ld = '1') then
            case (vector2_c) is
               when 0 => vector2 <= REG_V0Z;
               when 1 => vector2 <= REG_V1Z;
               when 2 => vector2 <= REG_V2Z;
               when 3 => vector2 <= REG_IR3;
               when others => null;
            end case;
         end if;
         if (translate0_ld = '1') then trCode(0) <= std_logic_vector(to_unsigned(translate0_c, 2)); end if;
         if (translate1_ld = '1') then trCode(1) <= std_logic_vector(to_unsigned(translate1_c, 2)); end if;
         if (translate2_ld = '1') then trCode(2) <= std_logic_vector(to_unsigned(translate2_c, 2)); end if;

         -- request assembly from the select codes (Pocket: compact operand multiplexers)
         if (mac0_mode = 1) then
            case (mac0_c1) is
               when 0 => mac0_v1 := IR1aspect;
               when 1 => mac0_v1 := resize(REG_IR2, 17);
               when 2 => mac0_v1 := resize(REG_DQA, 17);
               when 3 => mac0_v1 := IR1aspect_1;
               when 4 => mac0_v1 := resize(REG_IR2_1, 17);
               when 5 => mac0_v1 := IR1aspect_2;
               when 6 => mac0_v1 := resize(REG_IR2_2, 17);
               when 7 => mac0_v1 := resize(REG_SX0, 17);
               when 8 => mac0_v1 := resize(REG_SX1, 17);
               when 9 => mac0_v1 := resize(REG_SX2, 17);
               when 10 => mac0_v1 := '0' & signed(REG_SZ1);
               when 11 => mac0_v1 := '0' & signed(REG_SZ2);
               when 12 => mac0_v1 := '0' & signed(REG_SZ3);
               when 13 => mac0_v1 := '0' & signed(REG_SZ0);
               when others => null;
            end case;
            case (mac0_c2) is
               when 0 => mac0_v2 := '0' & signed(div_result);
               when 1 => mac0_v2 := resize(REG_SY1,18);
               when 2 => mac0_v2 := resize(REG_SY2,18);
               when 3 => mac0_v2 := resize(REG_SY0,18);
               when 4 => mac0_v2 := resize(ofVal(15 downto 0),18);  -- ZSF3 (ofCode 5)
               when 5 => mac0_v2 := resize(ofVal(15 downto 0),18);  -- ZSF4 (ofCode 6)
               when others => null;
            end case;
            case (mac0_c3) is
               when 0 => mac0_v3 := ofVal;  -- OFX (ofCode 0)
               when 1 => mac0_v3 := ofVal;  -- OFY (ofCode 1)
               when 2 => mac0_v3 := ofVal;  -- DQB (ofCode 4)
               when 3 => mac0_v3 := x"00000000";
               when others => null;
            end case;
            MAC0req <= (mac0_v1, mac0_v2, mac0_v3, mac0_fl(0), mac0_fl(1), mac0_fl(2), mac0_fl(3), mac0_fl(4), mac0_fl(5), mac0_fl(6));
         end if;
         if (mac1_mode /= 0) then
            case (mac1_cadd) is
               when 0 => mac1_vadd := resize(translate0, 33) & x"000";  -- TR (trCode 0)
               when 1 => mac1_vadd := to_signed(0, 45);
               when 2 => mac1_vadd := mac1Last;
               when others => null;
            end case;
         end if;
         if (mac1_mode = 1) then
            case (mac1_ca) is
               when 0 => mac1_va := resize(matrix00, 16);
               when 1 => mac1_va := resize(matrix01, 16);
               when 2 => mac1_va := resize(matrix02, 16);
               when 3 => mac1_va := resize(matrix11, 16);
               when 4 => mac1_va := resize(matrix22, 16);
               when 5 => mac1_va := resize(REG_IR1, 16);
               when others => null;
            end case;
            case (mac1_cb) is
               when 0 => mac1_vb := resize(vector0, 16);
               when 1 => mac1_vb := resize(vector1, 16);
               when 2 => mac1_vb := resize(vector2, 16);
               when 3 => mac1_vb := resize(REG_IR3, 16);
               when 4 => mac1_vb := resize(REG_IR2, 16);
               when 5 => mac1_vb := resize(REG_IR0, 16);
               when 6 => mac1_vb := resize(REG_IR1, 16);
               when 7 => mac1_vb := resize(signed(x"000000" & REG_RGBC( 7 downto  0)), 16);
               when others => null;
            end case;
            MAC1req <= mreq(mac1_va, mac1_vb, mac1_vadd, mac1_fl(0), mac1_fl(1), mac1_fl(2), mac1_fl(3), mac1_fl(4), mac1_fl(5), mac1_fl(6), mac1_fl(7), mac1_fl(8), mac1_fl(9));
         elsif (mac1_mode = 2) then
            case (mac1_cv) is
               when 0 => mac1_vv := resize(signed(x"000000" & calcColor( 7 downto  0)), 32);
               when 1 => mac1_vv := resize(translate0, 32);  -- FC (trCode 2)
               when 2 => mac1_vv := resize(resize(REG_IR1, 32), 32);
               when 3 => mac1_vv := resize(translate0, 32);
               when 4 => mac1_vv := resize(translate0, 32);  -- BK (trCode 1)
               when 5 => mac1_vv := resize(mac1_result, 32);
               when 6 => mac1_vv := resize(REG_MAC1, 32);
               when others => null;
            end case;
            case (mac1_csh) is
               when 0 => mac1_vsh := SH16;
               when 1 => mac1_vsh := SH12;
               when 2 => mac1_vsh := SH4;
               when 3 => mac1_vsh := shiftcode;
               when others => null;
            end case;
            MAC1req <= sreq(mac1_vv, mac1_vsh, mac1_vadd, mac1_fl(0), mac1_fl(1), mac1_fl(2), mac1_fl(3), mac1_fl(4), mac1_fl(5), mac1_fl(6), mac1_fl(7), mac1_fl(8), mac1_fl(9));
         end if;
         if (mac2_mode /= 0) then
            case (mac2_cadd) is
               when 0 => mac2_vadd := resize(translate1, 33) & x"000";  -- TR (trCode 0)
               when 1 => mac2_vadd := to_signed(0, 45);
               when 2 => mac2_vadd := mac2Last;
               when others => null;
            end case;
         end if;
         if (mac2_mode = 1) then
            case (mac2_ca) is
               when 0 => mac2_va := resize(matrix10, 16);
               when 1 => mac2_va := resize(matrix11, 16);
               when 2 => mac2_va := resize(matrix12, 16);
               when 3 => mac2_va := resize(matrix22, 16);
               when 4 => mac2_va := resize(matrix00, 16);
               when 5 => mac2_va := resize(REG_IR2, 16);
               when others => null;
            end case;
            case (mac2_cb) is
               when 0 => mac2_vb := resize(vector0, 16);
               when 1 => mac2_vb := resize(vector1, 16);
               when 2 => mac2_vb := resize(vector2, 16);
               when 3 => mac2_vb := resize(REG_IR1, 16);
               when 4 => mac2_vb := resize(REG_IR3, 16);
               when 5 => mac2_vb := resize(REG_IR0, 16);
               when 6 => mac2_vb := resize(REG_IR2, 16);
               when 7 => mac2_vb := resize(signed(x"000000" & REG_RGBC(15 downto  8)), 16);
               when others => null;
            end case;
            MAC2req <= mreq(mac2_va, mac2_vb, mac2_vadd, mac2_fl(0), mac2_fl(1), mac2_fl(2), mac2_fl(3), mac2_fl(4), mac2_fl(5), mac2_fl(6), mac2_fl(7), mac2_fl(8), mac2_fl(9));
         elsif (mac2_mode = 2) then
            case (mac2_cv) is
               when 0 => mac2_vv := resize(signed(x"000000" & calcColor(15 downto  8)), 32);
               when 1 => mac2_vv := resize(translate1, 32);  -- FC (trCode 2)
               when 2 => mac2_vv := resize(resize(REG_IR2, 32), 32);
               when 3 => mac2_vv := resize(translate1, 32);
               when 4 => mac2_vv := resize(translate1, 32);  -- BK (trCode 1)
               when 5 => mac2_vv := resize(mac2_result, 32);
               when 6 => mac2_vv := resize(REG_MAC2, 32);
               when others => null;
            end case;
            case (mac2_csh) is
               when 0 => mac2_vsh := SH16;
               when 1 => mac2_vsh := SH12;
               when 2 => mac2_vsh := SH4;
               when 3 => mac2_vsh := shiftcode;
               when others => null;
            end case;
            MAC2req <= sreq(mac2_vv, mac2_vsh, mac2_vadd, mac2_fl(0), mac2_fl(1), mac2_fl(2), mac2_fl(3), mac2_fl(4), mac2_fl(5), mac2_fl(6), mac2_fl(7), mac2_fl(8), mac2_fl(9));
         end if;
         if (mac3_mode /= 0) then
            case (mac3_cadd) is
               when 0 => mac3_vadd := resize(translate2, 33) & x"000";  -- TR (trCode 0)
               when 1 => mac3_vadd := to_signed(0, 45);
               when 2 => mac3_vadd := mac3Last;
               when others => null;
            end case;
         end if;
         if (mac3_mode = 1) then
            case (mac3_ca) is
               when 0 => mac3_va := resize(matrix20, 16);
               when 1 => mac3_va := resize(matrix21, 16);
               when 2 => mac3_va := resize(matrix22, 16);
               when 3 => mac3_va := resize(matrix00, 16);
               when 4 => mac3_va := resize(matrix11, 16);
               when 5 => mac3_va := resize(REG_IR3, 16);
               when others => null;
            end case;
            case (mac3_cb) is
               when 0 => mac3_vb := resize(vector0, 16);
               when 1 => mac3_vb := resize(vector1, 16);
               when 2 => mac3_vb := resize(vector2, 16);
               when 3 => mac3_vb := resize(REG_IR2, 16);
               when 4 => mac3_vb := resize(REG_IR1, 16);
               when 5 => mac3_vb := resize(REG_IR0, 16);
               when 6 => mac3_vb := resize(REG_IR3, 16);
               when 7 => mac3_vb := resize(signed(x"000000" & REG_RGBC(23 downto 16)), 16);
               when others => null;
            end case;
            MAC3req <= mreq(mac3_va, mac3_vb, mac3_vadd, mac3_fl(0), mac3_fl(1), mac3_fl(2), mac3_fl(3), mac3_fl(4), mac3_fl(5), mac3_fl(6), mac3_fl(7), mac3_fl(8), mac3_fl(9));
         elsif (mac3_mode = 2) then
            case (mac3_cv) is
               when 0 => mac3_vv := resize(signed(x"000000" & calcColor(23 downto 16)), 32);
               when 1 => mac3_vv := resize(translate2, 32);  -- FC (trCode 2)
               when 2 => mac3_vv := resize(resize(REG_IR3, 32), 32);
               when 3 => mac3_vv := resize(translate2, 32);
               when 4 => mac3_vv := resize(translate2, 32);  -- BK (trCode 1)
               when 5 => mac3_vv := resize(mac3_result, 32);
               when 6 => mac3_vv := resize(REG_MAC3, 32);
               when others => null;
            end case;
            case (mac3_csh) is
               when 0 => mac3_vsh := SH16;
               when 1 => mac3_vsh := SH12;
               when 2 => mac3_vsh := SH4;
               when 3 => mac3_vsh := shiftcode;
               when others => null;
            end case;
            MAC3req <= sreq(mac3_vv, mac3_vsh, mac3_vadd, mac3_fl(0), mac3_fl(1), mac3_fl(2), mac3_fl(3), mac3_fl(4), mac3_fl(5), mac3_fl(6), mac3_fl(7), mac3_fl(8), mac3_fl(9));
         end if;
            
            -- push RGB from MAC
            if (pushRGBfromMAC = '1') then
               if (mac1_result < 0) then
                  REG_FLAG(21) <= '1';
                  REG_RGB2(7 downto 0) <= (others => '0');
               elsif (unsigned(mac1_result(31 downto 4)) > 255) then
                  REG_FLAG(21) <= '1';
                  REG_RGB2(7 downto 0) <= (others => '1');
               else
                  REG_RGB2(7 downto 0) <= unsigned(mac1_result(11 downto 4));
               end if;
               
               if (mac2_result < 0) then
                  REG_FLAG(20) <= '1';
                  REG_RGB2(15 downto 8) <= (others => '0');
               elsif (unsigned(mac2_result(31 downto 4)) > 255) then
                  REG_FLAG(20) <= '1';
                  REG_RGB2(15 downto 8) <= (others => '1');
               else
                  REG_RGB2(15 downto 8) <= unsigned(mac2_result(11 downto 4));
               end if;
               
               if (mac3_result < 0) then
                  REG_FLAG(19) <= '1';
                  REG_RGB2(23 downto 16) <= (others => '0');
               elsif (unsigned(mac3_result(31 downto 4)) > 255) then
                  REG_FLAG(19) <= '1';
                  REG_RGB2(23 downto 16) <= (others => '1');
               else
                  REG_RGB2(23 downto 16) <= unsigned(mac3_result(11 downto 4));
               end if;
               
               REG_RGB2(31 downto 24) <= REG_RGBC(31 downto 24);
               REG_RGB0 <= REG_RGB1; REG_RGB1 <= REG_RGB2;
            
            end if;
            
            -- set OTZ
            if (setOTZ = '1') then
               if (mac0_result < 0) then
                  REG_OTZ <= (others => '0');
                  REG_FLAG(18) <= '1'; REG_FLAG(31) <= '1';
               elsif (mac0_result(34 downto 12) > 16#FFFF#) then
                  REG_OTZ <= (others => '1');
                  REG_FLAG(18) <= '1'; REG_FLAG(31) <= '1';
               else
                  REG_OTZ <= unsigned(mac0_result(27 downto 12));
               end if;
            end if;
            
            -- push sz and start divide
            if (pushSZandDivide = '1') then
               div_trigger <= '1';
               div_lhs     <= unsigned(ofVal(15 downto 0));  -- H (ofCode 2)
               if (mac3Shifted < 0) then
                  REG_FLAG(18) <= '1'; REG_FLAG(31) <= '1';
                  REG_SZ3      <= x"0000";
                  div_rhs      <= x"0000";
               elsif (mac3Shifted > 16#FFFF#) then
                  REG_FLAG(18) <= '1'; REG_FLAG(31) <= '1';
                  REG_SZ3      <= x"FFFF";
                  div_rhs      <= x"FFFF";
               else
                  REG_SZ3      <= unsigned(mac3Shifted(15 downto 0));
                  div_rhs      <= unsigned(mac3Shifted(15 downto 0));
               end if;
               REG_SZ0 <= REG_SZ1; REG_SZ1 <= REG_SZ2; REG_SZ2 <= REG_SZ3;
            end if;
            
            -- push SXY
            if (pushSXY = '1') then
               if (mac0Last(34 downto 16) < -1024) then
                  REG_SX2 <= to_signed(-1024, 16);
                  REG_FLAG(14) <= '1'; REG_FLAG(31) <= '1';
               elsif (mac0Last(34 downto 16) > 1023) then
                  REG_SX2 <= to_signed(1023, 16);  
                  REG_FLAG(14) <= '1'; REG_FLAG(31) <= '1';                           
               else
                  REG_SX2 <= mac0Last(31 downto 16);  
               end if;   
               if (mac0_result(34 downto 16) < -1024) then
                  REG_SY2 <= to_signed(-1024, 16);
                  REG_FLAG(13) <= '1'; REG_FLAG(31) <= '1';
               elsif (mac0_result(34 downto 16) > 1023) then
                  REG_SY2 <= to_signed(1023, 16);   
                  REG_FLAG(13) <= '1'; REG_FLAG(31) <= '1';                           
               else
                  REG_SY2 <= mac0_result(31 downto 16);  
               end if; 
               REG_SX0 <= REG_SX1; REG_SX1 <= REG_SX2;
               REG_SY0 <= REG_SY1; REG_SY1 <= REG_SY2;
            end if;
            
            -- writebacks
            if (mac0_writeback = '1') then REG_MAC0 <= mac0_result(31 downto 0); end if;
            if (mac1_writeback = '1') then REG_MAC1 <= mac1_result; end if;
            if (mac2_writeback = '1') then REG_MAC2 <= mac2_result; end if;
            if (mac3_writeback = '1') then REG_MAC3 <= mac3_result; end if;            
            
            if (ir0_writeback = '1') then REG_IR0 <= ir0_result; end if;
            if (ir1_writeback = '1') then REG_IR1 <= ir1_result; end if;
            if (ir2_writeback = '1') then REG_IR2 <= ir2_result; end if;
            if (ir3_writeback = '1') then REG_IR3 <= ir3_result; end if;
            
            -- flags
            if (flagMac0UF = '1') then REG_FLAG(15) <= '1'; REG_FLAG(31) <= '1'; end if;
            if (flagMac0OF = '1') then REG_FLAG(16) <= '1'; REG_FLAG(31) <= '1'; end if;            
            
            if (flagMac1UF = '1') then REG_FLAG(27) <= '1'; REG_FLAG(31) <= '1'; end if;
            if (flagMac1OF = '1') then REG_FLAG(30) <= '1'; REG_FLAG(31) <= '1'; end if;
            
            if (flagMac2UF = '1') then REG_FLAG(26) <= '1'; REG_FLAG(31) <= '1'; end if;
            if (flagMac2OF = '1') then REG_FLAG(29) <= '1'; REG_FLAG(31) <= '1'; end if;
            
            if (flagMac3UF = '1') then REG_FLAG(25) <= '1'; REG_FLAG(31) <= '1'; end if;
            if (flagMac3OF = '1') then REG_FLAG(28) <= '1'; REG_FLAG(31) <= '1'; end if;
            
            if (flagIR0 = '1') then REG_FLAG(12) <= '1'; end if;
            if (flagIR1 = '1') then REG_FLAG(24) <= '1'; REG_FLAG(31) <= '1'; end if;
            if (flagIR2 = '1') then REG_FLAG(23) <= '1'; REG_FLAG(31) <= '1'; end if;
            if (flagIR3 = '1') then REG_FLAG(22) <= '1'; end if;
            
            if (div_Error = '1') then REG_FLAG(17) <= '1'; REG_FLAG(31) <= '1'; end if;
         
         end if;
         
      end if;
   end process;
   
   -- processing units
   igte_mac0 : entity work.gte_mac0
   port map
   (
      clk2x          => clk2x,         
      MAC0req        => MAC0req,       
      mac0_result    => mac0_result,   
      mac0_writeback => mac0_writeback,
      ir_result      => ir0_result,   
      ir_writeback   => ir0_writeback,
      mac0Last       => mac0Last,
      flagMac0UF     => flagMac0UF,
      flagMac0OF     => flagMac0OF,
      flagIR         => flagIR0
   );
   
   igte_mac1 : entity work.gte_mac123s
   port map
   (
      clk2x          => clk2x,         
      MACreq         => MAC1req,       
      mac_result     => mac1_result,   
      mac_writeback  => mac1_writeback,
      ir_result      => ir1_result,   
      ir_writeback   => ir1_writeback,
      macLast        => mac1Last,
      flagMacUF      => flagMac1UF,
      flagMacOF      => flagMac1OF,
      flagIR         => flagIR1
   );
   
   igte_mac2 : entity work.gte_mac123s
   port map
   (
      clk2x          => clk2x,         
      MACreq         => MAC2req,       
      mac_result     => mac2_result,   
      mac_writeback  => mac2_writeback,
      ir_result      => ir2_result,   
      ir_writeback   => ir2_writeback,
      macLast        => mac2Last,
      flagMacUF      => flagMac2UF,
      flagMacOF      => flagMac2OF,
      flagIR         => flagIR2
   );
   
   igte_mac3 : entity work.gte_mac123s
   port map
   (
      clk2x          => clk2x,         
      MACreq         => MAC3req,       
      mac_result     => mac3_result,   
      mac_writeback  => mac3_writeback,
      ir_result      => ir3_result,   
      ir_writeback   => ir3_writeback,
      macLast        => mac3Last,
      macShifted     => mac3Shifted,
      flagMacUF      => flagMac3UF,
      flagMacOF      => flagMac3OF,
      flagIR         => flagIR3
   );
   
   igte_UNRDivide : entity work.gte_UNRDivide
   port map
   (
      clk2x          => clk2x,        
      trigger        => div_trigger,
      lhs            => div_lhs,    
      rhs            => div_rhs,    
      result         => div_result, 
      divError       => div_Error  
   );

   -- savestates are not supported in gte_small
   SS_DataRead <= (others => '0');
   SS_idle     <= '1';

end architecture;





