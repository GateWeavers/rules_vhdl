library ieee;
use ieee.std_logic_1164.all;

package interfaces_2019 is
    type streaming_bus is record
        valid : std_logic;
        data  : std_logic_vector(7 downto 0);
        ack   : std_logic;
    end record;

    view master_view of streaming_bus is
        valid : out;
        data  : out;
        ack   : in;
    end view;
end package;

library ieee;
use ieee.std_logic_1164.all;
use work.interfaces_2019.all;

entity test_view is
    port (
        clk    : in std_logic;
        m_axis : view master_view
    );
end entity;

architecture rtl of test_view is
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if m_axis.ack then
                m_axis.valid <= '1';
                m_axis.data  <= x"AB";
            else
                m_axis.valid <= '0';
                m_axis.data  <= x"XX";
            end if;
        end if;
    end process;
end architecture;
