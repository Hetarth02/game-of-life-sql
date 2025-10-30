drop function if exists generate_random_int;

create or replace function generate_random_int(min_num integer, max_num integer) returns integer
as $$
begin
	-- explanation: https://stackoverflow.com/questions/62981108/how-does-math-floormath-random-max-min-1-min-work-in-javascript
	return (select floor(random() * (max_num - min_num + 1)) + min_num);
end
$$ language plpgsql;

drop function if exists generate_random_bitstring;

create or replace function generate_random_bitstring(str_length integer) returns text
as $$
declare
	str text := '';
begin
	for i in 1 .. str_length loop
		-- Concate str with a '0' attached
		str := str || 0 || generate_random_int(0,1);
	end loop;
	return str;
end
$$ language plpgsql;

drop function if exists create_grid;

create or replace function create_grid(grid_rows integer, grid_cols integer) returns void
as $$
declare
	data_str text := '';
begin
	drop table if exists grid;

	execute 'create table if not exists grid (cell_values bit(' || 2 * grid_cols || '));';
	
	for row_counter in 1 .. grid_rows loop
		data_str := generate_random_bitstring(grid_cols);
		data_str := 'insert into grid (cell_values) values (' || E'b\'' || data_str || E'\'' || ');';
		execute data_str;
	end loop;
end
$$ language plpgsql;

drop function if exists current_generation;

create or replace function current_generation() returns table (cells text)
as $$
begin
	return query (select cell_values::text from grid);
end
$$ language plpgsql;

drop function if exists next_generation;

create or replace function next_generation() returns void
as $$
declare
	all_data text := '';
	new_all_data text := '';

	total_cols integer := 0;
	total_rows integer := 0;

	top_row text := 0;
	current_row text := 0;
	bottom_row text := 0;

	current_value integer := 0;

	top_left integer := 0;
	top_middle integer := 0;
	top_right integer := 0;

	middle_left integer := 0;
	middle_right integer := 0;

	bottom_left integer := 0;
	bottom_middle integer := 0;
	bottom_right integer := 0;

	live_neighbours integer := 0;

	bitmask text := '';
begin
	select string_agg(grid.cell_values::text, '') into all_data from grid;
	select bit_length(grid.cell_values) / 2 into total_cols from grid limit 1;
	total_rows := length(all_data)::integer / (2 * total_cols);

	for row_index in 1 .. total_rows loop
		top_row := repeat('0', total_cols * 2);
		if row_index - 1 != 0 then
			top_row := substr(all_data, ((row_index - 1) * total_cols * 2) - (total_cols * 2) + 1, total_cols * 2);
		end if;

		current_row := substr(all_data, (row_index * total_cols * 2) - (total_cols * 2) + 1, total_cols * 2);

		bottom_row := repeat('0', total_cols * 2);
		if row_index + 1 <= total_rows then
			bottom_row := substr(all_data, ((row_index + 1) * total_cols * 2) - (total_cols * 2) + 1, total_cols * 2);
		end if;

		for col_index in 1 .. total_cols loop
			-- We store the current value in right bit
			current_value := substr(current_row, (col_index * 2), 1)::integer;

			top_left := 0;
			middle_left := 0;
			bottom_left := 0;

			top_middle := 0;
			bottom_middle := 0;

			top_right := 0;
			middle_right := 0;
			bottom_right := 0;

			if col_index - 1 != 0 then
				top_left := substr(top_row, (col_index * 2) - 2, 1)::integer;
				middle_left := substr(current_row, (col_index * 2) - 2, 1)::integer;
				bottom_left := substr(bottom_row, (col_index * 2) - 2, 1)::integer;
			end if;

			top_middle := substr(top_row, (col_index * 2), 1)::integer;
			bottom_middle := substr(bottom_row, (col_index * 2), 1)::integer;

			if col_index + 1 <= total_cols then
				top_right := substr(top_row, (col_index * 2) + 2, 1)::integer;
				middle_right := substr(current_row, (col_index * 2) + 2, 1)::integer;
				bottom_right := substr(bottom_row, (col_index * 2) + 2, 1)::integer;
			end if;

			live_neighbours := 0;
			live_neighbours := top_left + top_middle + top_right + middle_left + middle_right + bottom_left + bottom_middle + bottom_right;

			-- We store the next value in left bit, hence only -1
			if current_value = 1 and (live_neighbours = 2 or live_neighbours = 3) then
				current_row := overlay(current_row placing '1' from (col_index * 2) - 1 for 1);
			elsif current_value = 0 and live_neighbours = 3 then
				current_row := overlay(current_row placing '1' from (col_index * 2) - 1 for 1);
			else
				current_row := overlay(current_row placing '0' from (col_index * 2) - 1 for 1);
			end if;
		end loop;

		new_all_data := new_all_data || current_row;
	end loop;

	execute 'truncate grid;';

	for i in 1 .. (total_cols * 2) loop
		if i % 2 = 1 then
			bitmask := bitmask || 1;
		else
			bitmask := bitmask || 0;
		end if;
	end loop;
	
	bitmask := E'b\'' || bitmask || E'\''; 

	for row_counter in 1 .. total_rows loop
	 	current_row := substr(new_all_data, (row_counter * total_cols * 2) - (total_cols * 2) + 1, total_cols * 2);
		current_row := E'b\'' || current_row || E'\'';
		current_row := '(' || current_row || ' & ' || bitmask || ') >> 1';
		current_row := 'insert into grid (cell_values) values (' || current_row || ');';
		execute current_row;
	end loop;
end
$$ language plpgsql;

do $$
begin
	-- Executes the function, discards the return value
    perform create_grid(5, 5);
end;
$$ language plpgsql;

select current_generation() as cells;

do $$
begin
	-- Executes the function, discards the return value
	perform next_generation();
end;
$$ language plpgsql;

select current_generation() as cells;