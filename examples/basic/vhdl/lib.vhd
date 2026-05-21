entity dummy is
    port (
        clk : in bit;
        q   : out bit
    );
end entity;

architecture rtl of dummy is
begin
    q <= clk;
end architecture;
