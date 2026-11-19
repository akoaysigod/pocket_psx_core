library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all;     

entity divider is
   generic
   (
      OUTREG    : boolean := true   -- false: quotient and remainder straight from the working registers (valid from done until the next start)
   );
   port 
   (
      clk       : in  std_logic;
      start     : in  std_logic;
      done      : out std_logic := '0';
      busy      : out std_logic := '0';
      dividend  : in  signed;
      divisor   : in  signed;
      quotient  : out signed;
      remainder : out signed
   );
end entity;

architecture arch of divider is

   -- Pocket: |dividend| leaves this register at the top, one bit per cycle, and the quotient bits enter at the bottom,
   -- so after the last cycle it holds the quotient. (The original kept dividend and quotient apart and addressed
   -- both with pointers.) Needs quotient and dividend of the same length, and remainder and divisor.
   signal work          : unsigned(dividend'length - 1 downto 0);
   signal divisor_r     : signed(divisor'length - 1 downto 0);   -- as given: Akku - |divisor| is an add or a subtract
   signal Akku          : unsigned(divisor'length downto 0);
   signal QPointer      : integer range quotient'length downto 0;
   signal done_buffer   : std_logic := '0';
   signal lastBit0      : std_logic := '0';   -- lowest quotient bit of the last division that ran to its end
   
   signal sign_dividend : std_logic := '0';
   signal sign_divisor  : std_logic := '0';
   
   signal quotNeg       : std_logic;
   signal quotient_r    : signed(quotient'length - 1 downto 0);
   signal remainder_r   : signed(remainder'length - 1 downto 0);
   
   -- OUTREG = false
   signal qMaskC        : unsigned(work'range);
   signal rMaskC        : unsigned(remainder'length - 1 downto 0);
   signal qCin          : unsigned(0 downto 0);
   signal rCin          : unsigned(0 downto 0);

begin 

   assert (quotient'length = dividend'length and remainder'length = divisor'length) report "divider: unsupported lengths" severity failure;
   
   quotNeg <= sign_dividend xor sign_divisor;
   
   -- OUTREG = false: straight from the working registers, which hold the results from the last cycle on
   qMaskC    <= (others => quotNeg);
   rMaskC    <= (others => sign_dividend);
   qCin(0)   <= quotNeg;
   rCin(0)   <= sign_dividend;
   
   quotient  <= quotient_r  when (OUTREG) else signed((work xor qMaskC) + qCin);
   remainder <= remainder_r when (OUTREG) else signed((Akku(remainder'length downto 1) xor rMaskC) + rCin);
   
   process (clk) is
      variable QPointerNew : integer range quotient'length downto 0;
      variable AkkuNew     : unsigned(Akku'range);
      variable Rdy_i       : std_logic;
      variable Q_bit       : std_logic;
      variable DiffX       : unsigned(Akku'length downto 0);
      variable Diff        : unsigned(Akku'range);
      variable divMask     : unsigned(Akku'range);
      variable oneShort    : std_logic;
      variable qView       : unsigned(work'range);
      variable rView       : unsigned(remainder'length - 1 downto 0);
      variable absMask     : unsigned(work'range);
      variable qMask       : unsigned(work'range);
      variable rMask       : unsigned(remainder'length - 1 downto 0);
      variable cin         : unsigned(0 downto 0);
   begin
      if rising_edge(clk) then

         done_buffer <= '0';
         busy        <= '0';
         
         -- the last cycle is still to come (state before this edge)
         oneShort := '0';
         if (Rdy_i = '0' and QPointer = 0) then
            oneShort := '1';
         end if;
         
         -- == Initialize loop ===============================================
         if start = '1' then
            
            busy    <= '1';
            
            -- |dividend|
            absMask := (others => dividend(dividend'left));
            cin(0)  := dividend(dividend'left);
            work    <= (unsigned(dividend) xor absMask) + cin;
            
            divisor_r     <= divisor;
            
            sign_dividend <= dividend(dividend'left);
            sign_divisor  <= divisor(divisor'left);
            
            QPointerNew := quotient'length;
            Rdy_i       := '0';
            AkkuNew     := (others => '0');
         -- == Repeat for every Digit in Q ===================================
         elsif Rdy_i = '0' then
            busy    <= '1';
            AkkuNew := Akku;
            QPointerNew := QPointer;        
            
            -- Akku - |divisor| in one adder: Akku + divisor for a negative divisor, else Akku - divisor
            divMask := (others => not sign_divisor);
            DiffX   := (AkkuNew & '1') + ((unsigned(resize(divisor_r, Akku'length)) xor divMask) & (not sign_divisor));
            Diff    := DiffX(Akku'length downto 1);
            if Diff(Diff'left) = '0' then              -- Does Y fit in Akku?
               Q_bit   := '1';                         -- YES: Digit is '1'
               AkkuNew := shift_left(Diff, 1);         --      Diff -> Akku
            else
               Q_bit   := '0';                         -- NO : Digit is '0'
               AkkuNew := shift_left(AkkuNew, 1);      --      Shift Akku
            end if;
            
            -- next dividend bit into Akku (in the last cycle that bit is no dividend bit any more, but nothing reads
            -- it: the remainder is taken above bit 0)
            AkkuNew(0) := work(work'left);
            
            if QPointerNew > 0 then                    -- Has this been the last cycle?
               QPointerNew := QPointerNew - 1;         -- NO : Prepare next cycle
            else
               Rdy_i       := '1';                     -- YES: work done
               done_buffer <= '1';
               lastBit0    <= Q_bit;
            end if;
            
            work <= work(work'left - 1 downto 0) & Q_bit;
         end if;

         QPointer  <= QPointerNew;
         Akku      <= AkkuNew;
         
         -- registered outputs (not used for OUTREG = false)
         -- One cycle before the end the original showed the new quotient bits down to bit 1 over bit 0 of the
         -- division before; gpu_poly's edge setup takes that value (baseStep one clock before done).
         if (oneShort = '1') then
            qView := work(work'left - 1 downto 0) & lastBit0;
         else
            qView := work;
         end if;
         qMask      := (others => quotNeg);
         cin(0)     := quotNeg;
         quotient_r <= signed((qView xor qMask) + cin);
         
         rView       := AkkuNew(remainder'length downto 1);
         rMask       := (others => sign_dividend);
         cin(0)      := sign_dividend;
         remainder_r <= signed((rView xor rMask) + cin);
         
         done <= done_buffer;
            
      end if;
   end process;
   
end architecture;
