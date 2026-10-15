-- ============================================================
-- EaseInn V1 — Storage Configuration for Guest ID Documents
-- ============================================================

-- Create bucket 'guest-documents' if it doesn't already exist
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'guest-documents',
  'guest-documents',
  false, -- private bucket, signed URLs or authenticated access only
  10485760, -- 10MB limit
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
)
ON CONFLICT (id) DO NOTHING;

-- Policies for guest-documents bucket
CREATE POLICY "Staff can view documents for their property"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'guest-documents'
    AND auth.role() = 'authenticated'
  );

CREATE POLICY "Staff can upload guest documents"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'guest-documents'
    AND auth.role() = 'authenticated'
  );

CREATE POLICY "Staff can update or delete guest documents"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'guest-documents'
    AND auth.role() = 'authenticated'
  );
