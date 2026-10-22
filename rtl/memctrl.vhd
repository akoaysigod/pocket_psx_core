library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

entity memctrl is
   port 
   (
      clk1x                : in  std_logic;
      ce                   : in  std_logic;
      reset                : in  std_logic;

      bus_addr             : in  unsigned(5 downto 0); 
      bus_dataWrite        : in  std_logic_vector(31 downto 0);
      bus_read             : in  std_logic;
      bus_write            : in  std_logic;
      bus_dataRead         : out std_logic_vector(31 downto 0);
      
      bus2_addr            : in  unsigned(3 downto 0); 
      bus2_dataWrite       : in  std_logic_vector(31 downto 0);
      bus2_read            : in  std_logic;
      bus2_write           : in  std_logic;
      bus2_dataRead        : out std_logic_vector(31 downto 0);
      
      errorBuswidth        : out std_logic;
      
      spu_memctrl          : out unsigned(13 downto 0);
      cd_memctrl           : out unsigned(13 downto 0);
      bios_memctrl         : out unsigned(13 downto 0);
      ex1_memctrl          : out unsigned(13 downto 0);
      ex2_memctrl          : out unsigned(13 downto 0);
      ex3_memctrl          : out unsigned(13 downto 0);
      
      com0_delay           : out unsigned(3 downto 0);
      com1_delay           : out unsigned(3 downto 0);
      com2_delay           : out unsigned(3 downto 0);
      com3_delay           : out unsigned(3 downto 0);
      
      dma_spu_timing_on    : out std_logic;
      dma_spu_timing_value : out unsigned(3 downto 0);
      
      loading_savestate    : in  std_logic;
      SS_reset             : in  std_logic;
      SS_DataWrite         : in  std_logic_vector(31 downto 0);
      SS_Adr               : in  unsigned(4 downto 0);
      SS_wren              : in  std_logic;
      SS_rden              : in  std_logic;
      SS_DataRead          : out std_logic_vector(31 downto 0)
   );
end entity;

architecture arch of memctrl is

   -- Pocket: the registers are kept in flip-flops only where the core uses them (bits 13:0 of the six
   -- device delay registers, SPU_DELAY bits 29 / 27:24, COMMON_DELAY 15:0). The CPU reads them back
   -- from a block-RAM copy holding each register's readback value, written together with the register;
   -- a register reads its reset value until written after reset (shadowValid). Bits a write leaves
   -- unchanged (30, 28 and 23:21 of the delay registers, 31:18 of COMMON_DELAY) are 0 from reset and
   -- stay 0. Savestate writes are not supported (SS_wren is constant 0 on the Pocket).
   -- shadow words: 0 EXP1_BASE, 1 EXP2_BASE, 2 EXP1_DELAY, 3 EXP3_DELAY, 4 BIOS_DELAY, 5 SPU_DELAY,
   -- 6 CDROM_DELAY, 7 EXP2_DELAY, 8 COMMON_DELAY (bus words 0-8), 9 RAMSIZE (bus2 word 0)
   type tResetValues is array(0 to 9) of std_logic_vector(31 downto 0);
   constant RESETVAL : tResetValues := (x"1F000000", x"1F802000", x"0013243F", x"00003022", x"0013243F",
                                        x"200931E1", x"00020843", x"00070777", x"00031125", x"00000B88");

   signal MC_EXP1_DELAY   : std_logic_vector(13 downto 0);
   signal MC_EXP3_DELAY   : std_logic_vector(13 downto 0);
   signal MC_BIOS_DELAY   : std_logic_vector(13 downto 0);
   signal MC_SPU_DELAY    : std_logic_vector(13 downto 0);
   signal MC_SPU_TIMING   : std_logic_vector(4 downto 0);   -- SPU_DELAY bits 29, 27:24
   signal MC_CDROM_DELAY  : std_logic_vector(13 downto 0);
   signal MC_EXP2_DELAY   : std_logic_vector(13 downto 0);
   signal MC_COMMON_DELAY : std_logic_vector(15 downto 0);

   type tShadowRam is array(0 to 15) of std_logic_vector(31 downto 0);
   signal shadowRam       : tShadowRam;
   signal shadowValid     : std_logic_vector(0 to 9) := (others => '0');
   signal shadowWe        : std_logic;
   signal shadowWa        : integer range 0 to 15;
   signal shadowWd        : std_logic_vector(31 downto 0);
   signal shadowRe        : std_logic;
   signal shadowRa        : integer range 0 to 15;
   signal shadowQ         : std_logic_vector(31 downto 0) := (others => '0');

   signal readBus         : std_logic := '0';   -- bus read of words 0-8 in the last enabled clock
   signal readBus2        : std_logic := '0';   -- bus2 read of RAMSIZE
   signal readBus2Ones    : std_logic := '0';   -- bus2 read of another address (all ones)
   signal readValid       : std_logic := '0';
   signal readWord        : integer range 0 to 9 := 0;
   signal readValue       : std_logic_vector(31 downto 0);

begin 

   errorBuswidth <= '1' when (MC_SPU_DELAY(12) = '0') else 
                    '0';
   
   spu_memctrl  <= unsigned(MC_SPU_DELAY);
   cd_memctrl   <= unsigned(MC_CDROM_DELAY);
   bios_memctrl <= unsigned(MC_BIOS_DELAY);
   ex1_memctrl  <= unsigned(MC_EXP1_DELAY);
   ex2_memctrl  <= unsigned(MC_EXP2_DELAY);
   ex3_memctrl  <= unsigned(MC_EXP3_DELAY);

   com0_delay   <= unsigned(MC_COMMON_DELAY( 3 downto  0));
   com1_delay   <= unsigned(MC_COMMON_DELAY( 7 downto  4));
   com2_delay   <= unsigned(MC_COMMON_DELAY(11 downto  8));
   com3_delay   <= unsigned(MC_COMMON_DELAY(15 downto 12));

   dma_spu_timing_on    <= MC_SPU_TIMING(4);
   dma_spu_timing_value <= unsigned(MC_SPU_TIMING(3 downto 0));

   -- same conditions as the register writes / reads in the process below
   process (reset, loading_savestate, SS_wren, ce, bus_addr, bus_dataWrite, bus_read, bus_write, bus2_addr, bus2_dataWrite, bus2_read, bus2_write)
   begin
      shadowWe <= '0';
      shadowWa <= to_integer(bus_addr(5 downto 2));
      shadowWd <= bus_dataWrite and x"AF1FFFFF";
      if (to_integer(bus_addr(5 downto 2)) <= 1) then
         shadowWd <= x"1F" & bus_dataWrite(23 downto 0);
      elsif (to_integer(bus_addr(5 downto 2)) = 8) then
         shadowWd <= x"000" & "00" & bus_dataWrite(17 downto 0);
      end if;
      if (not (reset = '1' and loading_savestate = '0') and SS_wren = '0' and ce = '1') then
         if (bus_write = '1' and bus_addr(1 downto 0) = "00" and to_integer(bus_addr(5 downto 2)) <= 8) then
            shadowWe <= '1';
         end if;
         if (bus2_write = '1' and bus2_addr = "0000") then
            shadowWe <= '1';
            shadowWa <= 9;
            shadowWd <= bus2_dataWrite;
         end if;
      end if;
      
      shadowRe <= '0';
      shadowRa <= to_integer(bus_addr(5 downto 2));
      if (bus2_read = '1') then
         shadowRa <= 9;
      end if;
      if (not (reset = '1' and loading_savestate = '0') and SS_wren = '0' and ce = '1' and (bus_read = '1' or bus2_read = '1')) then
         shadowRe <= '1';
      end if;
   end process;

   process (clk1x)
   begin
      if rising_edge(clk1x) then
         if (shadowWe = '1') then
            shadowRam(shadowWa) <= shadowWd;
         end if;
         if (shadowRe = '1') then
            shadowQ <= shadowRam(shadowRa);
         end if;
      end if;
   end process;

   readValue     <= shadowQ when (readValid = '1') else RESETVAL(readWord);
   bus_dataRead  <= readValue when (readBus = '1') else (others => '0');
   bus2_dataRead <= readValue when (readBus2 = '1') else (others => '1') when (readBus2Ones = '1') else (others => '0');
   
   process (clk1x)
   begin
      if rising_edge(clk1x) then
      
         if (reset = '1' and loading_savestate = '0') then
               
            MC_EXP1_DELAY   <= RESETVAL(2)(13 downto 0);
            MC_EXP3_DELAY   <= RESETVAL(3)(13 downto 0);
            MC_BIOS_DELAY   <= RESETVAL(4)(13 downto 0);
            MC_SPU_DELAY    <= RESETVAL(5)(13 downto 0);
            MC_SPU_TIMING   <= RESETVAL(5)(29) & RESETVAL(5)(27 downto 24);
            MC_CDROM_DELAY  <= RESETVAL(6)(13 downto 0);
            MC_EXP2_DELAY   <= RESETVAL(7)(13 downto 0);
            MC_COMMON_DELAY <= RESETVAL(8)(15 downto 0);
            shadowValid     <= (others => '0');
            
         elsif (SS_wren = '1') then

            -- synthesis translate_off
            report "memctrl: savestate loading is not supported" severity failure;
            -- synthesis translate_on

         elsif (ce = '1') then
         
            readBus      <= '0';
            readBus2     <= '0';
            readBus2Ones <= '0';

            -- bus read
            if (bus_read = '1' and to_integer(bus_addr(5 downto 2)) <= 8) then
               readBus   <= '1';
               readWord  <= to_integer(bus_addr(5 downto 2));
               readValid <= shadowValid(to_integer(bus_addr(5 downto 2)));
            end if;

            -- bus write
            if (bus_write = '1') then
               if (bus_addr(1 downto 0) = "00" and to_integer(bus_addr(5 downto 2)) <= 8) then
                  shadowValid(to_integer(bus_addr(5 downto 2))) <= '1';
               end if;
               case (to_integer(bus_addr(5 downto 0))) is
                  when 16#08# => MC_EXP1_DELAY   <= bus_dataWrite(13 downto 0);
                  when 16#0C# => MC_EXP3_DELAY   <= bus_dataWrite(13 downto 0);
                  when 16#10# => MC_BIOS_DELAY   <= bus_dataWrite(13 downto 0);
                  when 16#14# => MC_SPU_DELAY    <= bus_dataWrite(13 downto 0); MC_SPU_TIMING <= bus_dataWrite(29) & bus_dataWrite(27 downto 24);
                  when 16#18# => MC_CDROM_DELAY  <= bus_dataWrite(13 downto 0);
                  when 16#1C# => MC_EXP2_DELAY   <= bus_dataWrite(13 downto 0);
                  when 16#20# => MC_COMMON_DELAY <= bus_dataWrite(15 downto 0); 
                  when others => null;
               end case;
            end if;
            
            -- bus2 read
            if (bus2_read = '1') then
               readWord  <= 9;
               readValid <= shadowValid(9);
               if (bus2_addr = "0000") then
                  readBus2 <= '1';
               else
                  readBus2Ones <= '1';
               end if;
            end if;

            -- bus2 write
            if (bus2_write = '1' and bus2_addr = "0000") then
               shadowValid(9) <= '1';
            end if;

            -- synthesis translate_off
            assert ((bus_read or bus_write) and (bus2_read or bus2_write)) /= '1' report "memctrl: bus and bus2 accessed in the same clock" severity failure;
            -- synthesis translate_on
            
         end if;
      end if;
   end process;
   
   -- savestates are not supported (SS_rden is constant 0 on the Pocket)
   SS_DataRead <= (others => '0');

end architecture;
