library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.Numeric_Std.all;

-- Byte-addressable RAM primitive for the Livt `InternalRam` opaque component.
--
-- Timing contract:
-- - writes are synchronous and happen on the rising clock edge when the
--   corresponding write-enable byte lane is asserted
-- - the read address is registered on the rising clock edge
-- - read data is driven combinatorially from the registered read address
--
-- Current Livt/VHDL integration conventions:
-- - this context type import must be added manually for now; the `---` marker
--   lines are human-facing markers showing where this VHDL was manually
--   adjusted to match Livt-generated VHDL
-- - Livt currently binds opaque-component fields to VHDL ports with the
--   `ctor_` prefix, so these port names must stay aligned with the generated
--   wrapper until the convention changes
---
use work.livt_lang_icontext_package.t_icontext_in;
---

entity livt_io_internalram is
	generic (
		InitialCellValue : std_logic_vector := x"00"
	);
	port(
		---
		ctor_lvt_context_in : in t_icontext_in;
		---
		ctor_write_enable : in std_logic_vector;
		ctor_address : in std_logic_vector;
		ctor_write_data : in std_logic_vector;
		ctor_read_data : out std_logic_vector
	);
end;

architecture RTL of livt_io_internalram is

	constant BYTE_WIDTH : positive := 8;
	constant DATA_BYTE_COUNT : natural := ctor_write_data'length / BYTE_WIDTH;

	type T_Ram is array (0 to 2 ** ctor_address'length - 1) of std_logic_vector(ctor_write_data'range);

	signal internal_ram : T_Ram := (0 to 2 ** ctor_address'length - 1 => InitialCellValue);
	signal read_address : std_logic_vector(ctor_address'range) := (others => '0');
	
	signal clk : std_logic;

begin

	clk <= ctor_lvt_context_in.clk;

	assert ctor_write_data'length mod BYTE_WIDTH = 0
		report "InternalRam: write_data width must be a multiple of 8 bits"
		severity failure;

	assert ctor_write_enable'length = DATA_BYTE_COUNT
		report "InternalRam: write_enable must contain one lane per data byte"
		severity failure;

	assert InitialCellValue'length = ctor_write_data'length
		report "InternalRam: InitialCellValue width must match write_data width"
		severity failure;

	ram_proc : process(clk) is
	begin
		if rising_edge(clk) then
			for i in 0 to DATA_BYTE_COUNT - 1 loop
				if ctor_write_enable(i) = '1' then
					internal_ram(to_integer(unsigned(ctor_address)))(
						i * BYTE_WIDTH + BYTE_WIDTH - 1 downto i * BYTE_WIDTH
					) <=
						ctor_write_data(i * BYTE_WIDTH + BYTE_WIDTH - 1 downto i * BYTE_WIDTH);
				end if;
			end loop;
			read_address <= ctor_address;
		end if;
	end process ram_proc;

	ctor_read_data <= internal_ram(to_integer(unsigned(read_address)));

end;
