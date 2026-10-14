library ieee;
use ieee.std_logic_1164.all;

LIBRARY altera_mf;
USE altera_mf.altera_mf_components.all; 

-- Drop-in replacement for RamMLAB (registered write, unregistered "asynchronous" read) built on an
-- M10K block clocked on the falling edge of inclock. The read address is captured mid-cycle and
-- the data is ready before the next rising edge, so every value sampled on a rising edge equals
-- RamMLAB's. Writes land half a cycle earlier than in the MLAB; a read of the same address at that
-- moment returns the old data (OLD_DATA), exactly as the MLAB still holds the old value then.
-- Requirements: the write and read address/control inputs come from rising-edge logic (stable at
-- the falling edge), and q is only sampled on rising edges.
entity RamM10Kn is
   generic 
   (
      width           :  natural;
      width_byteena   :  natural := 1;
      widthad         :  natural
   );
   port 
   (
      inclock         : in std_logic;
      wren            : in std_logic;
      data            : in std_logic_vector(width-1 downto 0);
      wraddress       : in std_logic_vector(widthad-1 downto 0);
      rdaddress       : in std_logic_vector(widthad-1 downto 0);
      q               : out std_logic_vector(width-1 downto 0)
   );
end;

architecture rtl of RamM10Kn is

   signal clk_n : std_logic;

begin

   clk_n <= not inclock;

   ialtsyncram : altsyncram
   GENERIC MAP 
   (
      address_aclr_b                     => "NONE",
      address_reg_b                      => "CLOCK0",
      clock_enable_input_a               => "BYPASS",
      clock_enable_input_b               => "BYPASS",
      clock_enable_output_b              => "BYPASS",
      intended_device_family             => "Cyclone V",
      lpm_type                           => "altsyncram",
      numwords_a                         => 2**widthad,
      numwords_b                         => 2**widthad,
      operation_mode                     => "DUAL_PORT",
      outdata_aclr_b                     => "NONE",
      outdata_reg_b                      => "UNREGISTERED",
      power_up_uninitialized             => "FALSE",
      ram_block_type                     => "M10K",
      read_during_write_mode_mixed_ports => "OLD_DATA",
      widthad_a                          => widthad,
      widthad_b                          => widthad,
      width_a                            => width,
      width_b                            => width,
      width_byteena_a                    => 1
   )
   PORT MAP (
      clock0    => clk_n,
      wren_a    => wren,
      address_a => wraddress,
      data_a    => data,
      address_b => rdaddress,
      q_b       => q
   );

end rtl;
