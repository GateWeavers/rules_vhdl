library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library common_lib;
use common_lib.common_pkg.all;

entity counter is
    generic (
        WIDTH : integer := DEFAULT_WIDTH
    );
    port (
        clk   : in  std_logic;
        rst   : in  std_logic;
        count : out std_logic_vector(WIDTH - 1 downto 0)
    );
end entity counter;

architecture rtl of counter is
    signal r_count : unsigned(WIDTH - 1 downto 0);
begin
    process(clk, rst)
    begin
        if rst = '1' then
            r_count <= (others => '0');
        elsif rising_edge(clk) then
            r_count <= r_count + 1;
        end if;
    end process;
    count <= std_logic_vector(r_count);
end architecture rtl;
