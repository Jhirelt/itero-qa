-- Network and wand disconnections are separate origins (same list as ORIGINS in escalations/index.html).
alter table escalation_ticket_details drop constraint if exists escalation_ticket_details_origin_check;
update escalation_ticket_details set origin = null where origin = 'Recurrent connectivity (network / wand)';
alter table escalation_ticket_details add constraint escalation_ticket_details_origin_check check (origin is null or origin in (
  'RM replacement request', 'RM request', 'IL request', 'Management request', 'Internal team request',
  'Recurrent software issue', 'Outdated or wrong software version', 'Physical damage / out of warranty', 'Scan quality / lab rejection',
  'Customer dissatisfaction with process / delays', 'Admin / logistics request', 'Failed EFRA / reinstall', 'Replacement arrived faulty (DOA)',
  'Hardware failure', 'Recurrent network disconnections', 'Recurrent wand disconnections', 'Customer error / knowledge gap',
  'Not an escalation (already resolved / out of scope)', 'Internal process / documentation error'));
