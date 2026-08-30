library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.Numeric_Std.all;

use work.livt_lang_icontext_package.t_icontext_in;

entity livt_io_distributedram8x64 is
	port(
		ctor_lvt_context_in : in t_icontext_in;
		ctor_write_enable : in std_logic;
		ctor_address : in std_logic_vector(5 downto 0);
		ctor_write_data : in std_logic_vector(7 downto 0);
		ctor_read_data : out std_logic_vector(7 downto 0)
	);
end;

architecture RTL of livt_io_distributedram8x64 is
	type t_ram is array (0 to 63) of std_logic_vector(7 downto 0);
	signal ram : t_ram := (others => (others => '0'));
	attribute ram_style : string;
	attribute ram_style of ram : signal is "distributed";
begin
	write_proc : process(ctor_lvt_context_in.clk) is
	begin
		if rising_edge(ctor_lvt_context_in.clk) then
			if ctor_write_enable = '1' then
				ram(to_integer(unsigned(ctor_address))) <= ctor_write_data;
			end if;
		end if;
	end process;

	ctor_read_data <= ram(to_integer(unsigned(ctor_address)));
end;
