library ieee;
use ieee.std_logic_1164.all;

entity flat_io_test is
    port (
        clk          : in std_logic;
        input_data   : in std_logic_vector(7 downto 0);
        input_valid  : in std_logic;
        output_data  : out std_logic_vector(7 downto 0);
        output_valid : out std_logic
    );
end entity;

architecture rtl of flat_io_test is
begin
    process(clk)
    begin
        if rising_edge(clk) then
            output_data <= input_data;
            output_valid <= input_valid;
        end if;
    end process;
end architecture;
