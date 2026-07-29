library ieee;
use ieee.std_logic_1164.all;
use work.my_types.all;

entity tb_record_io is
end entity;

architecture sim of tb_record_io is
    signal clk    : std_logic := '0';
    signal input  : io_record := (data => (others => '0'), valid => '0');
    signal output : io_record;
begin
    clk <= not clk after 5 ns;

    dut : entity work.record_io_test
        port map (
            clk    => clk,
            input  => input,
            output => output
        );

    process
    begin
        wait for 20 ns;
        input.data <= x"AA";
        input.valid <= '1';
        wait for 10 ns;
        assert output.data = x"AA" report "Error: output mismatch" severity error;
        assert output.valid = '1' report "Error: valid mismatch" severity error;
        wait for 10 ns;
        -- Test complete
        std.env.finish;
    end process;
end architecture;
