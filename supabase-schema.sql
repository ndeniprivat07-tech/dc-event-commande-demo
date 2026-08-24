-- =====================================================================
--  DC EVENT COMMANDE — schéma Supabase
--
--  À exécuter tel quel dans l'éditeur SQL du projet Supabase, en une fois.
--  Le script est ré-exécutable : il ne détruit rien s'il tourne deux fois.
--
--  Principes retenus :
--   - les rôles de l'application (ADMIN / MANAGER / PRÉPARATEUR) sont portés
--     par une table « profils » adossée à l'authentification Supabase ;
--   - la sécurité est appliquée par la base (RLS), pas par l'application :
--     un utilisateur qui contournerait l'interface se heurterait quand même
--     aux mêmes règles ;
--   - le préparateur ne doit voir aucun montant. Comme RLS filtre les lignes
--     mais pas les colonnes, il passe par une VUE qui n'expose que la
--     logistique. C'est ce qui rend la règle réellement opposable, alors
--     qu'elle n'était qu'un choix d'affichage dans la version hors-ligne.
-- =====================================================================

-- ---------------------------------------------------------------------
--  1. Rôles et profils
-- ---------------------------------------------------------------------

do $$ begin
  create type role_app as enum ('ADMIN', 'MANAGER', 'PREPARATEUR');
exception when duplicate_object then null;
end $$;

create table if not exists profils (
  id          uuid primary key references auth.users(id) on delete cascade,
  nom         text        not null,
  role        role_app    not null default 'PREPARATEUR',
  actif       boolean     not null default true,
  cree_le     timestamptz not null default now()
);

comment on table profils is
  'Un profil par compte authentifié. Le rôle conditionne tous les droits.';

-- Rôle de l'utilisateur courant. STABLE + SECURITY DEFINER pour éviter une
-- récursion RLS quand les politiques interrogent cette même table.
create or replace function mon_role()
returns role_app
language sql
stable
security definer
set search_path = public
as $$
  select role from profils where id = auth.uid() and actif;
$$;

create or replace function est_admin()
returns boolean
language sql
stable
as $$ select mon_role() = 'ADMIN'; $$;

-- ---------------------------------------------------------------------
--  2. Catalogue
-- ---------------------------------------------------------------------

create table if not exists articles (
  ref          text primary key,
  nom          text    not null,
  categorie    text    not null,
  quantite     integer not null default 0 check (quantite >= 0),
  prix_jour    numeric(12,2) not null default 0 check (prix_jour >= 0),
  valeur_neuf  numeric(12,2) not null default 0 check (valeur_neuf >= 0),
  unite        text    not null default 'unité',
  -- Les photos vont dans le Storage Supabase, pas dans la base : c'est ce
  -- qui lève la limite de quelques mégaoctets de la version hors-ligne.
  photo_url    text,
  actif        boolean not null default true,
  modifie_le   timestamptz not null default now()
);

create index if not exists idx_articles_categorie on articles (categorie);

-- ---------------------------------------------------------------------
--  3. Commandes
-- ---------------------------------------------------------------------

do $$ begin
  create type statut_commande as enum
    ('DEVIS','RESERVEE','PREPAREE','LIVREE','RETOURNEE','FACTUREE','SOLDEE','ANNULEE');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type mode_reduction as enum ('pct','montant');
exception when duplicate_object then null;
end $$;

create table if not exists commandes (
  id                uuid primary key default gen_random_uuid(),
  numero            text unique not null,
  client            text not null,
  telephone         text,
  lieu              text,
  date_evenement    date not null,
  date_recuperation date not null,
  statut            statut_commande not null default 'DEVIS',

  -- Conditions financières. Une réduction se saisit en pourcentage ou en
  -- francs : le mode est conservé pour éviter les arrondis d'aller-retour.
  remise            numeric(12,2) not null default 0 check (remise >= 0),
  remise_mode       mode_reduction not null default 'pct',
  escompte          numeric(12,2) not null default 0 check (escompte >= 0),
  escompte_mode     mode_reduction not null default 'pct',
  transport         numeric(12,2) not null default 0 check (transport >= 0),
  transport_note    text,
  caution           numeric(12,2) not null default 0 check (caution >= 0),
  acompte           numeric(12,2) not null default 0 check (acompte >= 0),

  -- Facturation
  facture_numero    text unique,
  facture_le        date,

  -- Retour
  retour_le         date,
  retour_obs        text,
  retenues_faites   boolean not null default false,
  retenues_note     text,

  cree_par          uuid references profils(id),
  cree_le           timestamptz not null default now(),

  constraint dates_coherentes check (date_recuperation >= date_evenement)
);

create index if not exists idx_commandes_statut on commandes (statut);
create index if not exists idx_commandes_dates  on commandes (date_evenement, date_recuperation);

create table if not exists commande_lignes (
  id           bigserial primary key,
  commande_id  uuid not null references commandes(id) on delete cascade,
  article_ref  text not null references articles(ref) on delete restrict,
  qte          integer not null check (qte > 0),
  -- Prix figé à la commande : une hausse ultérieure du tarif ne doit pas
  -- réécrire une facture déjà émise.
  prix_jour    numeric(12,2) not null,
  unique (commande_id, article_ref)
);

create index if not exists idx_lignes_commande on commande_lignes (commande_id);
create index if not exists idx_lignes_article  on commande_lignes (article_ref);

-- ---------------------------------------------------------------------
--  4. Retour : constat puis chiffrage
--     Le préparateur constate (incidents), le manager chiffre (retenues).
--     Deux tables, deux droits : c'est la séparation des rôles inscrite
--     dans le modèle et non plus seulement dans l'interface.
-- ---------------------------------------------------------------------

do $$ begin
  create type type_incident as enum ('CASSE','MANQUANT');
exception when duplicate_object then null;
end $$;

create table if not exists retour_incidents (
  id           bigserial primary key,
  commande_id  uuid not null references commandes(id) on delete cascade,
  article_ref  text not null references articles(ref),
  type         type_incident not null,
  qte          integer not null check (qte > 0),
  note         text,
  constate_par uuid references profils(id),
  constate_le  timestamptz not null default now()
);

create table if not exists retenues (
  id           bigserial primary key,
  commande_id  uuid not null references commandes(id) on delete cascade,
  article_ref  text not null references articles(ref),
  type         type_incident not null,
  qte          integer not null check (qte > 0),
  montant      numeric(12,2) not null check (montant >= 0),
  arbitre_par  uuid references profils(id),
  arbitre_le   timestamptz not null default now()
);

-- ---------------------------------------------------------------------
--  5. Encaissements
-- ---------------------------------------------------------------------

create table if not exists paiements (
  id           bigserial primary key,
  commande_id  uuid not null references commandes(id) on delete cascade,
  -- Négatif pour une restitution de caution : la caisse se lit en une somme.
  montant      numeric(12,2) not null,
  mode         text not null,
  date_reglement date not null default current_date,
  saisi_par    uuid references profils(id),
  saisi_le     timestamptz not null default now()
);

create index if not exists idx_paiements_commande on paiements (commande_id);

-- ---------------------------------------------------------------------
--  6. Validations — le cœur du cahier des charges
--     Retirer un article, annuler une commande ou dépasser le seuil de
--     réduction exige l'accord de l'ADMIN, avec un motif conservé.
-- ---------------------------------------------------------------------

do $$ begin
  create type type_validation as enum ('RETRAIT','ANNULATION','REMISE');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type statut_validation as enum ('EN_ATTENTE','APPROUVEE','REFUSEE');
exception when duplicate_object then null;
end $$;

create table if not exists validations (
  id            bigserial primary key,
  commande_id   uuid not null references commandes(id) on delete cascade,
  type          type_validation not null,
  motif         text not null check (length(btrim(motif)) > 0),
  charge        jsonb not null default '{}'::jsonb,
  statut        statut_validation not null default 'EN_ATTENTE',
  demandeur     uuid references profils(id),
  demande_le    timestamptz not null default now(),
  decideur      uuid references profils(id),
  decide_le     timestamptz,
  commentaire   text
);

create index if not exists idx_validations_attente
  on validations (statut) where statut = 'EN_ATTENTE';

-- ---------------------------------------------------------------------
--  7. Traçabilité — en insertion seule, personne ne réécrit l'histoire
-- ---------------------------------------------------------------------

create table if not exists journal (
  id       bigserial primary key,
  quand    timestamptz not null default now(),
  qui      uuid references profils(id),
  nom      text,
  role     role_app,
  action   text not null,
  detail   text,
  cible    uuid
);

create index if not exists idx_journal_quand on journal (quand desc);

-- ---------------------------------------------------------------------
--  8. Paramètres de la société
-- ---------------------------------------------------------------------

create table if not exists parametres (
  cle     text primary key,
  valeur  jsonb not null,
  modifie_le timestamptz not null default now()
);

insert into parametres (cle, valeur) values
  ('societe', '{"nom":"DEALS CENTER",
                "activite":"Location de matériel événementiel et décoration",
                "ville":"Abidjan, Côte d''Ivoire",
                "tel":"","mail":"","rccm":"","cc":"","delai_reglement":30}'::jsonb),
  ('seuil_reduction', '10'::jsonb)
on conflict (cle) do nothing;

-- ---------------------------------------------------------------------
--  9. Disponibilité — le stock est un calendrier, pas un compteur
-- ---------------------------------------------------------------------

create or replace function disponible(
  p_article text,
  p_debut   date,
  p_fin     date,
  p_sauf    uuid default null
)
returns integer
language sql
stable
as $$
  select coalesce(a.quantite, 0) - coalesce((
    select sum(cl.qte)
    from commande_lignes cl
    join commandes c on c.id = cl.commande_id
    where cl.article_ref = p_article
      and (p_sauf is null or c.id <> p_sauf)
      and c.statut in ('RESERVEE','PREPAREE','LIVREE')
      -- Chevauchement de périodes
      and c.date_evenement <= p_fin
      and p_debut <= c.date_recuperation
  ), 0)::integer
  from articles a
  where a.ref = p_article;
$$;

comment on function disponible is
  'Quantité réellement disponible sur une période. Un devis ne bloque rien.';

-- ---------------------------------------------------------------------
--  10. Vue du dépôt — aucune donnée financière
--      RLS filtre les lignes mais pas les colonnes : c'est cette vue qui
--      garantit que le préparateur ne voit aucun montant.
-- ---------------------------------------------------------------------

create or replace view commandes_depot
with (security_invoker = true)
as
select
  c.id, c.numero, c.client, c.telephone, c.lieu,
  c.date_evenement, c.date_recuperation, c.statut,
  c.retour_le, c.retour_obs,
  (select coalesce(sum(cl.qte),0) from commande_lignes cl where cl.commande_id = c.id) as pieces
from commandes c
where c.statut in ('RESERVEE','PREPAREE','LIVREE','RETOURNEE');

create or replace view lignes_depot
with (security_invoker = true)
as
select cl.id, cl.commande_id, cl.article_ref, cl.qte,
       a.nom, a.categorie, a.photo_url
from commande_lignes cl
join articles a on a.ref = cl.article_ref;

-- ---------------------------------------------------------------------
--  11. Sécurité au niveau des lignes
-- ---------------------------------------------------------------------

alter table profils           enable row level security;
alter table articles          enable row level security;
alter table commandes         enable row level security;
alter table commande_lignes   enable row level security;
alter table retour_incidents  enable row level security;
alter table retenues          enable row level security;
alter table paiements         enable row level security;
alter table validations       enable row level security;
alter table journal           enable row level security;
alter table parametres        enable row level security;

-- Profils : chacun lit le sien, l'ADMIN gère tout le monde
drop policy if exists p_profils_lecture on profils;
create policy p_profils_lecture on profils for select
  using (id = auth.uid() or est_admin());

drop policy if exists p_profils_admin on profils;
create policy p_profils_admin on profils for all
  using (est_admin()) with check (est_admin());

-- Catalogue : tout le monde consulte, seul l'ADMIN modifie
drop policy if exists p_articles_lecture on articles;
create policy p_articles_lecture on articles for select
  using (mon_role() is not null);

drop policy if exists p_articles_ecriture on articles;
create policy p_articles_ecriture on articles for all
  using (est_admin()) with check (est_admin());

-- Commandes : le préparateur passe par la vue, pas par la table
drop policy if exists p_commandes_lecture on commandes;
create policy p_commandes_lecture on commandes for select
  using (mon_role() in ('ADMIN','MANAGER'));

drop policy if exists p_commandes_ecriture on commandes;
create policy p_commandes_ecriture on commandes for insert
  with check (mon_role() in ('ADMIN','MANAGER'));

-- Le préparateur fait avancer la logistique, sans toucher au reste :
-- la contrainte porte sur les états, l'application ne peut pas y déroger.
drop policy if exists p_commandes_maj on commandes;
create policy p_commandes_maj on commandes for update
  using (
    mon_role() in ('ADMIN','MANAGER')
    or (mon_role() = 'PREPARATEUR' and statut in ('RESERVEE','PREPAREE','LIVREE'))
  )
  with check (
    mon_role() in ('ADMIN','MANAGER')
    or (mon_role() = 'PREPARATEUR' and statut in ('PREPAREE','LIVREE','RETOURNEE'))
  );

drop policy if exists p_commandes_suppr on commandes;
create policy p_commandes_suppr on commandes for delete using (est_admin());

-- Lignes de commande
drop policy if exists p_lignes_lecture on commande_lignes;
create policy p_lignes_lecture on commande_lignes for select
  using (mon_role() is not null);

drop policy if exists p_lignes_ecriture on commande_lignes;
create policy p_lignes_ecriture on commande_lignes for all
  using (mon_role() in ('ADMIN','MANAGER'))
  with check (mon_role() in ('ADMIN','MANAGER'));

-- Constat de retour : c'est le travail du préparateur
drop policy if exists p_incidents_lecture on retour_incidents;
create policy p_incidents_lecture on retour_incidents for select
  using (mon_role() is not null);

drop policy if exists p_incidents_ecriture on retour_incidents;
create policy p_incidents_ecriture on retour_incidents for insert
  with check (mon_role() in ('ADMIN','MANAGER','PREPARATEUR'));

-- Chiffrage des dégâts : jamais le préparateur
drop policy if exists p_retenues_lecture on retenues;
create policy p_retenues_lecture on retenues for select
  using (mon_role() in ('ADMIN','MANAGER'));

drop policy if exists p_retenues_ecriture on retenues;
create policy p_retenues_ecriture on retenues for all
  using (mon_role() in ('ADMIN','MANAGER'))
  with check (mon_role() in ('ADMIN','MANAGER'));

-- Encaissements
drop policy if exists p_paiements_lecture on paiements;
create policy p_paiements_lecture on paiements for select
  using (mon_role() in ('ADMIN','MANAGER'));

drop policy if exists p_paiements_ecriture on paiements;
create policy p_paiements_ecriture on paiements for insert
  with check (mon_role() in ('ADMIN','MANAGER'));

-- Validations : le manager demande, seul l'ADMIN tranche.
-- La règle est ici inviolable, alors qu'elle reposait sur l'interface.
drop policy if exists p_validations_lecture on validations;
create policy p_validations_lecture on validations for select
  using (mon_role() in ('ADMIN','MANAGER'));

drop policy if exists p_validations_demande on validations;
create policy p_validations_demande on validations for insert
  with check (mon_role() in ('ADMIN','MANAGER') and statut = 'EN_ATTENTE');

drop policy if exists p_validations_decision on validations;
create policy p_validations_decision on validations for update
  using (est_admin()) with check (est_admin());

-- Journal : tout le monde écrit, personne ne modifie ni n'efface
drop policy if exists p_journal_lecture on journal;
create policy p_journal_lecture on journal for select using (est_admin());

drop policy if exists p_journal_ecriture on journal;
create policy p_journal_ecriture on journal for insert
  with check (mon_role() is not null);

-- Paramètres
drop policy if exists p_param_lecture on parametres;
create policy p_param_lecture on parametres for select
  using (mon_role() is not null);

drop policy if exists p_param_ecriture on parametres;
create policy p_param_ecriture on parametres for all
  using (est_admin()) with check (est_admin());

-- ---------------------------------------------------------------------
--  12. Garde-fou : une réduction au-delà du seuil doit être validée
--      Le contrôle est en base : passer par l'API ne permet pas de le
--      contourner, contrairement à la version hors-ligne.
-- ---------------------------------------------------------------------

create or replace function verifier_reduction()
returns trigger
language plpgsql
as $$
declare
  v_brut    numeric := 0;
  v_remise  numeric := 0;
  v_escompte numeric := 0;
  v_jours   integer;
  v_seuil   numeric;
  v_taux    numeric;
begin
  if mon_role() = 'ADMIN' then
    return new;                       -- l'ADMIN décide directement
  end if;

  v_jours := greatest(1, (new.date_recuperation - new.date_evenement) + 1);

  select coalesce(sum(cl.qte * cl.prix_jour * v_jours), 0)
    into v_brut
    from commande_lignes cl
   where cl.commande_id = new.id;

  if v_brut = 0 then return new; end if;

  v_remise   := least(case when new.remise_mode = 'montant'
                           then new.remise else v_brut * new.remise / 100 end, v_brut);
  v_escompte := case when new.escompte_mode = 'montant'
                     then new.escompte else (v_brut - v_remise) * new.escompte / 100 end;

  select (valeur #>> '{}')::numeric into v_seuil from parametres where cle = 'seuil_reduction';
  v_seuil := coalesce(v_seuil, 10);

  v_taux := (v_remise + v_escompte) / v_brut * 100;

  if v_taux > v_seuil then
    raise exception
      'Réduction de % %% supérieure au seuil de % %% : une validation ADMIN est requise.',
      round(v_taux, 1), v_seuil;
  end if;

  return new;
end $$;

drop trigger if exists t_verifier_reduction on commandes;
create trigger t_verifier_reduction
  before insert or update of remise, remise_mode, escompte, escompte_mode
  on commandes
  for each row execute function verifier_reduction();

-- ---------------------------------------------------------------------
--  13. Stockage des photos
-- ---------------------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('photos-articles', 'photos-articles', true)
on conflict (id) do nothing;

drop policy if exists p_photos_lecture on storage.objects;
create policy p_photos_lecture on storage.objects for select
  using (bucket_id = 'photos-articles');

drop policy if exists p_photos_ecriture on storage.objects;
create policy p_photos_ecriture on storage.objects for all
  using (bucket_id = 'photos-articles' and est_admin())
  with check (bucket_id = 'photos-articles' and est_admin());

-- =====================================================================
--  APRÈS EXÉCUTION
--
--  1. Créer les comptes dans Authentication → Users (un par personne).
--  2. Leur donner un rôle, en remplaçant les identifiants ci-dessous :
--
--     insert into profils (id, nom, role) values
--       ('<uuid-du-compte>', 'M. Bamba', 'ADMIN'),
--       ('<uuid-du-compte>', 'Konan',    'MANAGER'),
--       ('<uuid-du-compte>', 'Sery',     'PREPARATEUR');
--
--  3. Renseigner les mentions légales réelles :
--
--     update parametres
--        set valeur = valeur || '{"rccm":"...","cc":"...","tel":"...","mail":"..."}'::jsonb
--      where cle = 'societe';
--
--  4. Relever l'URL du projet et la clé « anon » dans Project Settings → API,
--     puis les saisir dans l'écran « Serveur » de l'application.
-- =====================================================================
