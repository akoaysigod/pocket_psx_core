-- Equivalence test: rtl/joypad_pad.vhd (joypad_pad_new) against the joypad_pad before the Pocket
-- trims (joypad_pad_ref, = upstream). Random SIO byte traffic on the pad's port signals (protocol bytes
-- 01 / 42 / 43-4D / 00 and random ones, deselects, port changes, ce gaps, resets) with the pad
-- configuration of the Pocket (port 1 digital pad with random keys, port 2 off); with ANYPAD the pad type
-- of port 1 changes at random (all types, NeGcon rumble on / off) to check the parts that hold for every
-- pad type. Every output is compared on every clock.
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

use work.pJoypad.all;

entity tb_joypad_pad is
   generic
   (
      NUM_CYCLES : integer := 2000000;
      SEED       : integer := 1;
      ANYPAD     : boolean := false
   );
end entity;

architecture sim of tb_joypad_pad is

   signal clk1x         : std_logic := '1';
   signal ce            : std_logic := '1';
   signal reset         : std_logic := '1';
   signal joypad1       : joypad_t;
   signal joypad2       : joypad_t;
   signal neGconRumble  : std_logic := '0';
   signal portNr        : integer range 0 to 1 := 0;
   signal selected      : std_logic := '0';
   signal actionNext    : std_logic := '0';
   signal transmitting  : std_logic := '0';
   signal transmitValue : std_logic_vector(7 downto 0) := (others => '0');
   signal slotIdle      : std_logic := '1';

   type tOut is record
      isActive      : std_logic;
      receiveValid  : std_logic;
      receiveBuffer : std_logic_vector(7 downto 0);
      ack           : std_logic;
      padMode       : std_logic_vector(1 downto 0);
      justif        : std_logic_vector(1 downto 0);
      rumble1       : std_logic_vector(15 downto 0);
      rumble2       : std_logic_vector(15 downto 0);
      ss_out        : std_logic_vector(31 downto 0);
   end record;
   signal o_ref, o_new : tOut;

   signal mismatches : integer := 0;
   signal acks       : integer := 0;
   signal bytes      : integer := 0;
   signal done       : boolean := false;

   function pad(t : integer; keys : std_logic_vector(15 downto 0)) return joypad_t is
      variable j : joypad_t;
   begin
      j.PadPortEnable := '1'; j.PadPortDigital := '0'; j.PadPortAnalog := '0'; j.PadPortMouse := '0'; j.PadPortGunCon := '0';
      j.PadPortNeGcon := '0'; j.PadPortJustif := '0'; j.PadPortDS := '0'; j.PadPortStick := '0'; j.PadPortPopn := '0';
      case t is
         when 0 => j.PadPortDigital := '1';
         when 1 => j.PadPortAnalog := '1';
         when 2 => j.PadPortMouse := '1';
         when 3 => j.PadPortGunCon := '1';
         when 4 => j.PadPortNeGcon := '1';
         when 5 => j.PadPortJustif := '1';
         when 6 => j.PadPortDS := '1';
         when 7 => j.PadPortStick := '1';
         when others => j.PadPortEnable := '0';
      end case;
      j.WheelMap := '0'; j.ToggleDS := '0';
      j.KeyTriangle := keys(0); j.KeyCircle := keys(1); j.KeyCross := keys(2); j.KeySquare := keys(3);
      j.KeySelect := keys(4); j.KeyStart := keys(5); j.KeyRight := keys(6); j.KeyLeft := keys(7);
      j.KeyUp := keys(8); j.KeyDown := keys(9); j.KeyR1 := keys(10); j.KeyR2 := keys(11);
      j.KeyR3 := keys(12); j.KeyL1 := keys(13); j.KeyL2 := keys(14); j.KeyL3 := keys(15);
      j.Analog1X := (others => '0'); j.Analog1Y := (others => '0'); j.Analog2X := (others => '0'); j.Analog2Y := (others => '0');
      return j;
   end function;

begin

   clk1x <= not clk1x after 5 ns when not done;

   gdut : for k in 0 to 1 generate
      signal o : tOut;
   begin
      gref : if k = 0 generate
         idut : entity work.joypad_pad_ref
         port map (clk1x => clk1x, ce => ce, reset => reset, DSAltSwitchMode => '0', isMultitap => '0', multitapDigital => '0', multitapAnalog => '0',
                   joypad1 => joypad1, joypad2 => joypad2, joypad3 => joypad2, joypad4 => joypad2,
                   joypad1_rumble => o.rumble1, joypad2_rumble => o.rumble2, joypad3_rumble => open, joypad4_rumble => open,
                   neGconRumble => neGconRumble, padMode => o.padMode, portNr => portNr, isPal => '0',
                   selected => selected, actionNext => actionNext, transmitting => transmitting, transmitValue => transmitValue,
                   isActive => o.isActive, slotIdle => slotIdle, receiveValid => o.receiveValid, receiveBuffer => o.receiveBuffer, ack => o.ack,
                   MouseEvent => '0', MouseLeft => '0', MouseRight => '0', MouseX => (others => '0'), MouseY => (others => '0'),
                   GunX => to_unsigned(128, 8), GunY_scanlines => to_unsigned(120, 9), GunAimOffscreen => '0', JustifierIrqEnable => o.justif,
                   ss_in => (others => '0'), ss_out => o.ss_out);
         o_ref <= o;
      end generate;
      gnew : if k = 1 generate
         idut : entity work.joypad_pad_new
         port map (clk1x => clk1x, ce => ce, reset => reset, DSAltSwitchMode => '0', isMultitap => '0', multitapDigital => '0', multitapAnalog => '0',
                   joypad1 => joypad1, joypad2 => joypad2, joypad3 => joypad2, joypad4 => joypad2,
                   joypad1_rumble => o.rumble1, joypad2_rumble => o.rumble2, joypad3_rumble => open, joypad4_rumble => open,
                   neGconRumble => neGconRumble, padMode => o.padMode, portNr => portNr, isPal => '0',
                   selected => selected, actionNext => actionNext, transmitting => transmitting, transmitValue => transmitValue,
                   isActive => o.isActive, slotIdle => slotIdle, receiveValid => o.receiveValid, receiveBuffer => o.receiveBuffer, ack => o.ack,
                   MouseEvent => '0', MouseLeft => '0', MouseRight => '0', MouseX => (others => '0'), MouseY => (others => '0'),
                   GunX => to_unsigned(128, 8), GunY_scanlines => to_unsigned(120, 9), GunAimOffscreen => '0', JustifierIrqEnable => o.justif,
                   ss_in => (others => '0'), ss_out => o.ss_out);
         o_new <= o;
      end generate;
   end generate;

   stim : process
      variable s1, s2 : positive;
      variable r : real;
      variable c : integer := 0;
      variable keys : std_logic_vector(15 downto 0) := (others => '0');
      variable ptype : integer := 0;
      variable b : integer;
      impure function rnd(n : integer) return integer is
      begin
         uniform(s1, s2, r);
         return integer(floor(r * real(n)));
      end function;
      procedure tick is
      begin
         wait until rising_edge(clk1x);
         c := c + 1;
         actionNext <= '0';
         reset      <= '0';
         ce         <= '1';
         if (rnd(10) = 0) then ce <= '0'; end if;
         if (rnd(300000) = 0) then reset <= '1'; end if;
         if (rnd(5000) = 0) then keys := std_logic_vector(to_unsigned(rnd(65536), 16)); end if;
         if (ANYPAD and rnd(20000) = 0) then ptype := rnd(9); neGconRumble <= '1' when rnd(2) = 0 else '0'; end if;
         joypad1 <= pad(ptype, keys);
      end procedure;
   begin
      s1 := SEED; s2 := SEED * 31 + 7;
      joypad2 <= pad(8, x"0000");   -- port 2: no pad (PadPortEnable = '0')
      joypad1 <= pad(0, x"0000");
      for i in 0 to 9 loop tick; end loop;
      while (c < NUM_CYCLES) loop
         -- one transfer: select, a few bytes, deselect
         if (rnd(8) = 0) then portNr <= 1; else portNr <= 0; end if;
         selected     <= '1';
         slotIdle     <= '1';
         if (rnd(20) = 0) then slotIdle <= '0'; end if;
         transmitting <= '1';
         for n in 0 to rnd(12) loop
            -- protocol bytes: start 01, read 42, DualShock config 43-47 / 4C / 4D, 00 / 01 arguments, random
            case rnd(16) is
               when 0 | 1 | 2 => b := 16#01#;
               when 3 | 4     => b := 16#42#;
               when 5         => b := 16#43#;
               when 6         => b := 16#44#;
               when 7         => b := 16#45#;
               when 8         => b := 16#46#;
               when 9         => b := 16#47#;
               when 10        => b := 16#4C#;
               when 11        => b := 16#4D#;
               when 12        => b := 16#00#;
               when others    => b := rnd(256);
            end case;
            if (n = 0 and rnd(4) /= 0) then b := 16#01#; end if;
            transmitValue <= std_logic_vector(to_unsigned(b, 8));
            for i in 0 to rnd(6) loop tick; end loop;
            actionNext <= '1';
            bytes <= bytes + 1;
            tick;
            for i in 0 to 4 + rnd(40) loop tick; end loop;
         end loop;
         if (rnd(3) /= 0) then
            transmitting <= '0';
            selected     <= '0';
            for i in 0 to rnd(50) loop tick; end loop;
         end if;
      end loop;
      done <= true;
      wait for 20 ns;
      report "DONE cycles=" & integer'image(c) & " bytes=" & integer'image(bytes) & " acks=" & integer'image(acks) & " mismatch_cycles=" & integer'image(mismatches);
      if (mismatches = 0 and acks > 1000) then report "PASS"; else report "FAIL"; end if;
      wait;
   end process;

   check : process (clk1x)
   begin
      if falling_edge(clk1x) then
         if (o_ref /= o_new) then
            if (mismatches < 10) then
               report "mismatch: ref ack " & std_logic'image(o_ref.ack) & " rv " & std_logic'image(o_ref.receiveValid) & " rb " & to_hstring(o_ref.receiveBuffer) &
                      " | new ack " & std_logic'image(o_new.ack) & " rv " & std_logic'image(o_new.receiveValid) & " rb " & to_hstring(o_new.receiveBuffer) severity warning;
            end if;
            mismatches <= mismatches + 1;
         end if;
         if (o_ref.ack = '1') then acks <= acks + 1; end if;
      end if;
   end process;

end architecture;
