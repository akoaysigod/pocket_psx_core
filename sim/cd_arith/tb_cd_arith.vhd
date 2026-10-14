-- Exhaustive check of the divider-free helpers in cd_top against the original
-- expressions: getSectorsPerTrack over every LBA, modSmall over every
-- (phy_oldOffset + 1, phy_spt) pair, toBCD7 over every 7-bit frame value.
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use STD.textio.all;

entity tb_cd_arith is
end entity;

architecture sim of tb_cd_arith is
   constant FRAMES_PER_MINUTE : integer := 75 * 60;

   function sptOld(lba : integer) return integer is
      variable mm : integer;
   begin
      mm := lba / FRAMES_PER_MINUTE;
      if (mm = 0) then return 8;
      elsif (mm <= 4) then return 9;
      elsif (mm <= 7) then return 10;
      elsif (mm <= 11) then return 11;
      elsif (mm <= 16) then return 12;
      elsif (mm <= 23) then return 13;
      elsif (mm <= 27) then return 14;
      elsif (mm <= 32) then return 15;
      elsif (mm <= 39) then return 16;
      elsif (mm <= 44) then return 17;
      elsif (mm <= 52) then return 18;
      elsif (mm <= 60) then return 19;
      elsif (mm <= 67) then return 20;
      elsif (mm <= 74) then return 21;
      else return 22;
      end if;
   end function;

   -- copied verbatim from rtl/cd_top.vhd by run.sh
   --INSERT_NEW_FUNCTIONS
begin
   process
      variable errors : integer := 0;
      variable l : line;
   begin
      for lba in 0 to 524287 loop
         if (sptOld(lba) /= getSectorsPerTrack(lba)) then
            errors := errors + 1;
         end if;
      end loop;
      for off in 0 to 31 loop
         for spt in 8 to 22 loop
            if (((off + 1) mod spt) /= modSmall(off + 1, spt)) then
               errors := errors + 1;
            end if;
         end loop;
      end loop;
      for f in 0 to 127 loop
         if (toBCD7(to_unsigned(f, 7)) /= std_logic_vector(resize(to_unsigned(f, 7) / 10, 4)) & std_logic_vector(resize(to_unsigned(f, 7) mod 10, 4))) then
            errors := errors + 1;
         end if;
      end loop;
      write(l, string'("checked 524288 LBAs, 480 offset/spt pairs and 128 BCD frames, errors=") & integer'image(errors));
      writeline(output, l);
      if (errors = 0) then write(l, string'("PASS")); else write(l, string'("FAIL")); end if;
      writeline(output, l);
      wait;
   end process;
end architecture;
