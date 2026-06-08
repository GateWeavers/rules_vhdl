library ieee;
use ieee.std_logic_1164.all;

library vunit_lib;
context vunit_lib.vunit_context;

library lib;

entity e2e_tb is
    generic (
        runner_cfg : string
    );
end entity;

architecture sim of e2e_tb is
    signal clk : bit := '0';
    signal q   : bit;
begin
    main : process
    begin
        test_runner_setup(runner, runner_cfg);
        test_runner_cleanup(runner);
        wait;
    end process;
    dut: entity lib.dummy
        port map (
            clk => clk,
            q   => q
        );
    
    process
    begin
        clk <= '1';
        wait for 10 ns;
        clk <= '0';
        wait for 10 ns;
        assert false report "End of simulation" severity note;
        wait;
    end process;
end architecture;
