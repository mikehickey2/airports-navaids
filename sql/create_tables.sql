-- Drop existing tables if they exist
DROP TABLE IF EXISTS airports;
DROP TABLE IF EXISTS navaids;

-- Create airports table (lowercase column names)
CREATE TABLE airports (
  id SERIAL PRIMARY KEY,
  eff_date DATE,
  site_no TEXT,
  site_type_code TEXT,
  state_code TEXT,
  arpt_id TEXT,
  city TEXT,
  country_code TEXT,
  state_name TEXT,
  county_name TEXT,
  arpt_name TEXT,
  lat_deg INTEGER,
  lat_min INTEGER,
  lat_sec NUMERIC,
  lat_hemis TEXT,
  lat_decimal NUMERIC,
  long_deg INTEGER,
  long_min INTEGER,
  long_sec NUMERIC,
  long_hemis TEXT,
  long_decimal NUMERIC,
  elev NUMERIC,
  elev_method_code TEXT,
  mag_varn NUMERIC,
  mag_hemis TEXT,
  mag_varn_year INTEGER,
  icao_id TEXT,
  facility_use TEXT
);

-- Create navaids table (lowercase column names)
CREATE TABLE navaids (
  id SERIAL PRIMARY KEY,
  eff_date DATE,
  nav_id TEXT,
  nav_type TEXT,
  state_code TEXT,
  city TEXT,
  country_code TEXT,
  name TEXT,
  state_name TEXT,
  region_code TEXT,
  lat_hemis TEXT,
  lat_deg INTEGER,
  lat_min INTEGER,
  lat_sec NUMERIC,
  lat_decimal NUMERIC,
  long_hemis TEXT,
  long_deg INTEGER,
  long_min INTEGER,
  long_sec NUMERIC,
  long_decimal NUMERIC,
  elev NUMERIC,
  mag_varn NUMERIC,
  mag_varn_hemis TEXT,
  mag_varn_year INTEGER,
  alt_code TEXT
);

-- Enable Row Level Security
ALTER TABLE airports ENABLE ROW LEVEL SECURITY;
ALTER TABLE navaids ENABLE ROW LEVEL SECURITY;

-- Create policies for public read access
CREATE POLICY "Allow public read access on airports" ON airports
  FOR SELECT USING (true);

CREATE POLICY "Allow public read access on navaids" ON navaids
  FOR SELECT USING (true);

-- Write access: secret key (sb_secret_...) bypasses RLS entirely
-- No INSERT/DELETE policies needed - pipeline uses secret key
-- Public key (sb_publishable_...) is read-only via SELECT policy above

-- Data API: least-privilege grants
-- Required for tables created in `public` after 2026-10-30 on existing
-- projects (Supabase removes auto-grants then). REVOKE statements ensure
-- least-privilege regardless of when this schema is applied — before the
-- cutoff Supabase auto-grants ALL privileges to anon/authenticated, so
-- this strips that back to read-only via RLS + SELECT only.
-- See: https://github.com/orgs/supabase/discussions/45329

REVOKE ALL ON public.airports FROM anon, authenticated, service_role;
REVOKE ALL ON public.navaids  FROM anon, authenticated, service_role;
REVOKE ALL ON SEQUENCE public.airports_id_seq, public.navaids_id_seq
  FROM anon, authenticated;

-- anon: read-only (publishable key)
GRANT SELECT ON public.airports TO anon;
GRANT SELECT ON public.navaids  TO anon;

-- authenticated: read-only (defensive; project has no auth flow today)
GRANT SELECT ON public.airports TO authenticated;
GRANT SELECT ON public.navaids  TO authenticated;

-- service_role: full DML + sequence access (secret key / pipeline)
GRANT SELECT, INSERT, UPDATE, DELETE ON public.airports TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.navaids  TO service_role;
GRANT USAGE, SELECT ON SEQUENCE public.airports_id_seq, public.navaids_id_seq
  TO service_role;