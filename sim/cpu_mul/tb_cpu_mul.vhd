-- Checks the CPU multiplier merge (rtl/cpu.vhd): MULT/MULTU via one 33x33 signed multiply with
-- sign/zero-extended operands gives the same 64-bit HI:LO as the original separate signed and
-- unsigned 32x32 multiplies. Corner values x corner values, then NUM random pairs.
-- MUTATE=1 zero-extends MULT operands (checker sensitivity).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity tb_cpu_mul is
   generic (NUM : integer := 2000000; SEED : integer := 1; MUTATE : integer := 0);
end entity;

architecture sim of tb_cpu_mul is
begin
   process
      type tcorner is array(natural range <>) of unsigned(31 downto 0);
      constant corners : tcorner := (x"00000000", x"00000001", x"FFFFFFFF", x"80000000", x"7FFFFFFF", x"80000001",
                                     x"FFFFFFFE", x"00010000", x"0000FFFF", x"FFFF0000", x"00000800", x"FFFFF800", x"12345678");
      variable s1 : positive := 11 + SEED;
      variable s2 : positive := 7777;
      variable r  : real;
      variable a, b : unsigned(31 downto 0);
      variable errors, checks : integer := 0;
      variable oldS : signed(63 downto 0);
      variable oldU : unsigned(63 downto 0);
      variable newR : signed(65 downto 0);
      variable sgn  : std_logic;
      impure function rnd32 return unsigned is
         variable v : unsigned(31 downto 0);
      begin
         for i in 0 to 3 loop uniform(s1, s2, r); v(i*8+7 downto i*8) := to_unsigned(integer(trunc(r * 256.0)) mod 256, 8); end loop;
         return v;
      end function;
      procedure check(x, y : unsigned(31 downto 0)) is
      begin
         oldS := signed(x) * signed(y);
         oldU := x * y;
         for m in 0 to 1 loop
            if m = 0 then sgn := '1'; else sgn := '0'; end if;   -- 1 = MULT, 0 = MULTU
            if MUTATE = 1 then sgn := '0'; end if;
            newR := signed((sgn and x(31)) & x) * signed((sgn and y(31)) & y);
            checks := checks + 1;
            if m = 0 and std_logic_vector(newR(63 downto 0)) /= std_logic_vector(oldS) then errors := errors + 1; end if;
            if m = 1 and std_logic_vector(newR(63 downto 0)) /= std_logic_vector(oldU) then errors := errors + 1; end if;
         end loop;
      end procedure;
   begin
      for i in corners'range loop
         for j in corners'range loop
            check(corners(i), corners(j));
         end loop;
      end loop;
      for n in 1 to NUM loop
         a := rnd32; b := rnd32;
         uniform(s1, s2, r);
         if r < 0.1 then a := resize(a(11 downto 0), 32); elsif r < 0.2 then a := not resize(a(11 downto 0), 32); end if;
         check(a, b);
      end loop;
      report "DONE checks=" & integer'image(checks) & " errors=" & integer'image(errors);
      if errors = 0 then report "PASS"; else report "FAIL"; end if;
      wait;
   end process;
end architecture;
