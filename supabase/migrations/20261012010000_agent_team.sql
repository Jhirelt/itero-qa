-- Agents belong to one team, NA or CALA; teams are shown and averaged apart.
alter table public.agents add column if not exists team text not null default 'NA';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'agents_team_check') then
    alter table public.agents add constraint agents_team_check check (team in ('NA', 'CALA'));
  end if;
end $$;
update public.agents set team = 'CALA' where name in (
  'Andres Pedreros', 'Carlos Espinoza Tres', 'Daniel Guedez', 'Diana Camila Pena', 'Johnny Chacon',
  'Maria Jose Vargas Vera-Cruz', 'Marianny Vivas', 'Rudy Castillo', 'Walter Daniels'
);
