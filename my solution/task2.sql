create schema if not exists test;

-- создаем табличкуу для сырых данных
drop table if exists test.amb;

create table if not exists test.amb(
ckey int,
cref int,
cnum int2,
cend int2,
textcode varchar(16),
name varchar(128)
);

/*
заполняем итоговую таблицу значения, которые нужно обработать.
предварительно переводим данные из формата *.dbf в формат *.csv
любой прогой по желанию. Фрагмент преобразованных данных прикладываю 
к решению. Преобразованный файл нужно положить в директорию
/raw-data/amb.csv в контейнере с посгрей
*/
copy test.amb
from '/raw-data/amb.csv'
with (format csv, delimiter ';', header, encoding 'win1251')
;

--функция получения родительского textcode
create or replace function test.get_parent_textcode(current_textcode character varying)
 returns character varying
 language plpgsql
as $function$
declare
    parts text[];
    parent_textcode varchar;
begin
    parts := string_to_array(trim(both '.' from current_textcode), '.');
    if array_length(parts, 1) > 1 then
        parent_textcode := array_to_string(parts[1:array_length(parts, 1)-1], '.') || '.';
        return parent_textcode;
    end if;
    
    return null;
end;
$function$
;

create or replace procedure test.migrate_data()
language plpgsql
as $$
declare
    rec record;
    parent_rec record;
    counter integer := 0;
    current_cref integer;
    current_cnum integer;
begin
    create temp table amb_temp as 
    select *, row_number() over (order by textcode) as temp_id 
    from test.amb 
    order by textcode;
    
    update amb_temp set ckey = null, cref = null, cnum = null, cend = null;
    
    update amb_temp set ckey = temp_id;
    
    for rec in
         select * from amb_temp order by textcode
    -- записывает для каждой записи cref родителя который определяем по текущему textcode
    -- и textcode из фукции поиска радительского кода
    loop
        select 
            subq.cur_textcode_array[cardinality(subq.cur_textcode_array)]::int2 into current_cnum
        from (
            select string_to_array(trim(both '.' from textcode), '.')::int[] as cur_textcode_array
            from amb_temp) as subq
        ;
    
        select
            ckey into current_cref
        from amb_temp 
        where textcode = test.get_parent_textcode(rec.textcode);
        
        update amb_temp set
        cref = current_cref,
        cnum = current_cnum
        where temp_id = rec.temp_id;
    end loop;

    update amb_temp set cend = 0;

    update amb_temp 
    set cend = 1 
    where ckey in (
        select distinct cref 
        from amb_temp 
        where cref is not null
    );
    
    update test.amb 
    set ckey = t.ckey,
        cref = t.cref,
        cnum = t.cnum,
        cend = t.cend
    from amb_temp t
    where test.amb.textcode = t.textcode and amb.name = t.name;
    
    drop table amb_temp;
    
end;
$$;

call test.migrate_data();