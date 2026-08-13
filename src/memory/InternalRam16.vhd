library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.Numeric_Std.all;

use work.livt_lang_icontext_package.t_icontext_in;

entity livt_io_internalram16 is
	port(
		ctor_lvt_context_in : in t_icontext_in;
		ctor_write_enable : in std_logic_vector(1 downto 0);
		ctor_address : in std_logic_vector(10 downto 0);
		ctor_write_data : in std_logic_vector(15 downto 0);
		ctor_read_data : out std_logic_vector(15 downto 0)
	);
end;

architecture RTL of livt_io_internalram16 is
	type T_Ram is array (0 to 2047) of std_logic_vector(15 downto 0);
	signal internal_ram : T_Ram := (others => (others => '0'));
	signal read_address : std_logic_vector(10 downto 0) := (others => '0');
begin
	ram_proc : process(ctor_lvt_context_in.clk) is
	begin
		if rising_edge(ctor_lvt_context_in.clk) then
			for lane in 0 to 1 loop
				if ctor_write_enable(lane) = '1' then
					internal_ram(to_integer(unsigned(ctor_address)))(
						lane * 8 + 7 downto lane * 8) <=
						ctor_write_data(lane * 8 + 7 downto lane * 8);
				end if;
			end loop;
			read_address <= ctor_address;
		end if;
	end process ram_proc;

	read_proc : process(all) is
	begin
		if is_x(read_address) then
			ctor_read_data <= (others => '0');
		else
			ctor_read_data <= internal_ram(to_integer(unsigned(read_address)));
		end if;
	end process read_proc;
end;
