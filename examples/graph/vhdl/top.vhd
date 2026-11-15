library ieee;
use ieee.std_logic_1164.all;

library common_lib;
use common_lib.common_pkg.all;

entity top is
    generic (
        WIDTH : integer := DEFAULT_WIDTH
    );
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        out_val : out std_logic_vector(WIDTH - 1 downto 0)
    );
end entity top;

architecture rtl of top is
    signal s_count : std_logic_vector(WIDTH - 1 downto 0);
begin
    u_counter: entity work.counter
        generic map (
            WIDTH => WIDTH
        )
        port map (
            clk   => clk,
            rst   => rst,
            count => s_count
        );

    u_reg_file: entity work.reg_file
        generic map (
            DEPTH => 16,
            WIDTH => WIDTH
        )
        port map (
            clk  => clk,
            we   => '1',
            din  => s_count,
            dout => out_val
        );
end architecture rtl;
