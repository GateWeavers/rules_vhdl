library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity counter is
    generic (
        LIMIT : integer := 255
    );
    port (
        clk   : in  std_logic;
        rst   : in  std_logic;
        en    : in  std_logic;
        count : out std_logic_vector(7 downto 0)
    );
end entity counter;

architecture rtl of counter is
    signal r_count : unsigned(7 downto 0) := (others => '0');
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                r_count <= (others => '0');
            elsif en = '1' then
                if r_count = to_unsigned(LIMIT, 8) then
                    r_count <= (others => '0');
                else
                    r_count <= r_count + 1;
                end if;
            end if;
        end if;
    end process;

    count <= std_logic_vector(r_count);

    -- Embedded PSL Assertion: Reset forces counter to 0
    -- psl default clock is rising_edge(clk);
    -- psl assert always (rst = '1' -> next r_count = 0);

end architecture rtl;
