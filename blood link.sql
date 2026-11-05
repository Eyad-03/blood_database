-- BloodLink database schema - SQL Server 2016+
CREATE DATABASE BloodLink;
GO
USE BloodLink;
GO

/* ===================== LOOKUP TABLES ===================== */
CREATE TABLE cities (
  id    SMALLINT IDENTITY(1,1) PRIMARY KEY,
  name  NVARCHAR(60) NOT NULL UNIQUE
);

CREATE TABLE blood_types (
  code  VARCHAR(3) PRIMARY KEY
);

CREATE TABLE blood_compatibility (
  donor_type      VARCHAR(3) NOT NULL REFERENCES blood_types(code),
  recipient_type  VARCHAR(3) NOT NULL REFERENCES blood_types(code),
  PRIMARY KEY (donor_type, recipient_type)
);

CREATE TABLE event_types (
  id    TINYINT IDENTITY(1,1) PRIMARY KEY,
  name  NVARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE ad_plans (
  code           VARCHAR(20) PRIMARY KEY,
  name           NVARCHAR(40) NOT NULL,
  duration_days  SMALLINT NOT NULL CHECK (duration_days > 0),
  price_jod      DECIMAL(8,2) NOT NULL CHECK (price_jod >= 0),
  perks          NVARCHAR(MAX) NULL CHECK (perks IS NULL OR ISJSON(perks) = 1)
);

CREATE TABLE ad_departments (
  id    TINYINT IDENTITY(1,1) PRIMARY KEY,
  name  NVARCHAR(60) NOT NULL UNIQUE
);

CREATE TABLE ad_categories (
  id     TINYINT IDENTITY(1,1) PRIMARY KEY,
  name   NVARCHAR(60) NOT NULL UNIQUE,
  color  CHAR(7)      NULL,
  icon   VARCHAR(30)  NULL
);

/* ===================== ACCOUNTS ===================== */
CREATE TABLE users (
  id             INT IDENTITY(1,1) PRIMARY KEY,
  role           VARCHAR(10)   NOT NULL CHECK (role IN ('donor','requester','hospital','admin')),
  full_name      NVARCHAR(80)  NOT NULL,
  email          NVARCHAR(120) NOT NULL UNIQUE,
  phone          VARCHAR(20)   NULL,
  password_hash  VARCHAR(255)  NOT NULL,
  city_id        SMALLINT      NULL REFERENCES cities(id),
  location_text  NVARCHAR(120) NULL,
  is_active      BIT           NOT NULL DEFAULT 1,
  consent_at     DATETIME2     NULL,
  last_login_at  DATETIME2     NULL,
  created_at     DATETIME2     NOT NULL DEFAULT SYSDATETIME(),
  updated_at     DATETIME2     NOT NULL DEFAULT SYSDATETIME()
);
CREATE INDEX idx_users_role ON users(role);

CREATE TABLE donor_profiles (
  user_id                 INT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  blood_type              VARCHAR(3)    NOT NULL REFERENCES blood_types(code),
  area                    NVARCHAR(80)  NULL,
  latitude                DECIMAL(9,6)  NULL,
  longitude               DECIMAL(9,6)  NULL,
  location_mode           VARCHAR(12)   NOT NULL DEFAULT 'approximate'
                          CHECK (location_mode IN ('approximate','precise')),
  is_available            BIT           NOT NULL DEFAULT 0,
  availability_window     VARCHAR(10)   NULL
                          CHECK (availability_window IN ('today','tomorrow','week','contact')),
  preferred_contact       VARCHAR(5)    NOT NULL DEFAULT 'phone'
                          CHECK (preferred_contact IN ('phone','sms','email')),
  notes                   NVARCHAR(350) NULL,
  share_location_consent  BIT           NOT NULL DEFAULT 0,
  last_donation_date      DATE          NULL,
  updated_at              DATETIME2     NOT NULL DEFAULT SYSDATETIME()
);
CREATE INDEX idx_donor_search ON donor_profiles(blood_type, is_available);

CREATE TABLE requester_profiles (
  user_id              INT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  required_blood_type  VARCHAR(3) NULL REFERENCES blood_types(code),  -- NULL = "Not sure"
  request_city_id      SMALLINT   NULL REFERENCES cities(id)
);

CREATE TABLE organizations (
  id                INT IDENTITY(1,1) PRIMARY KEY,
  code              VARCHAR(20)   NOT NULL UNIQUE,
  owner_user_id     INT           NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  name              NVARCHAR(120) NOT NULL,
  org_type          VARCHAR(25)   NOT NULL
                    CHECK (org_type IN ('Hospital','Blood donation center','Medical center')),
  city_id           SMALLINT      NOT NULL REFERENCES cities(id),
  address           NVARCHAR(160) NULL,
  license_number    VARCHAR(40)   NULL,
  email             NVARCHAR(120) NOT NULL,
  phone             VARCHAR(20)   NULL,
  contact_person    NVARCHAR(80)  NULL,
  status            VARCHAR(10)   NOT NULL DEFAULT 'Pending'
                    CHECK (status IN ('Pending','Active','Rejected')),
  rejection_reason  NVARCHAR(500) NULL,
  registered_at     DATETIME2     NOT NULL DEFAULT SYSDATETIME(),
  decided_at        DATETIME2     NULL,
  decided_by        INT           NULL REFERENCES users(id)
);
CREATE UNIQUE INDEX uq_org_license ON organizations(license_number) WHERE license_number IS NOT NULL;
CREATE INDEX idx_org_status ON organizations(status);

CREATE TABLE organization_documents (
  id               INT IDENTITY(1,1) PRIMARY KEY,
  organization_id  INT           NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  doc_type         VARCHAR(30)   NOT NULL
                   CHECK (doc_type IN ('moh_license','registration_certificate','representative_id')),
  file_name        NVARCHAR(160) NOT NULL,
  file_path        NVARCHAR(255) NOT NULL,
  file_size_bytes  INT           NULL,
  is_checked       BIT           NOT NULL DEFAULT 0,
  uploaded_at      DATETIME2     NOT NULL DEFAULT SYSDATETIME(),
  CONSTRAINT uq_orgdoc_type UNIQUE (organization_id, doc_type)
);

/* ===================== BLOOD REQUESTS / DONATIONS / INVENTORY ===================== */
CREATE TABLE blood_requests (
  id             INT IDENTITY(1,1) PRIMARY KEY,
  code           VARCHAR(20)   NOT NULL UNIQUE,
  requester_id   INT           NOT NULL REFERENCES users(id),
  donor_id       INT           NOT NULL REFERENCES users(id),
  hospital_id    INT           NULL REFERENCES organizations(id),
  hospital_name  NVARCHAR(120) NULL,
  blood_type     VARCHAR(3)    NOT NULL REFERENCES blood_types(code),
  units          TINYINT       NOT NULL DEFAULT 1 CHECK (units BETWEEN 1 AND 20),
  priority       VARCHAR(6)    NOT NULL DEFAULT 'Normal' CHECK (priority IN ('Normal','High','Urgent')),
  message        NVARCHAR(500) NULL,
  location_text  NVARCHAR(120) NULL,
  status         VARCHAR(10)   NOT NULL DEFAULT 'Pending'
                 CHECK (status IN ('Pending','Accepted','Declined','Completed','Cancelled')),
  created_at     DATETIME2     NOT NULL DEFAULT SYSDATETIME(),
  responded_at   DATETIME2     NULL,
  completed_at   DATETIME2     NULL,
  CONSTRAINT chk_br_parties CHECK (requester_id <> donor_id)
);
CREATE INDEX idx_br_donor_status     ON blood_requests(donor_id, status);
CREATE INDEX idx_br_requester_status ON blood_requests(requester_id, status);

CREATE TABLE donations (
  id                INT IDENTITY(1,1) PRIMARY KEY,
  donor_id          INT         NOT NULL REFERENCES users(id),
  blood_request_id  INT         NULL REFERENCES blood_requests(id),
  organization_id   INT         NULL REFERENCES organizations(id),
  units             TINYINT     NOT NULL DEFAULT 1 CHECK (units BETWEEN 1 AND 20),
  donated_at        DATETIME2   NOT NULL DEFAULT SYSDATETIME(),
  source            VARCHAR(20) NOT NULL DEFAULT 'self_reported'
                    CHECK (source IN ('self_reported','hospital_verified'))
);
CREATE INDEX idx_don_donor_date ON donations(donor_id, donated_at);

CREATE TABLE donation_verifications (
  id               INT IDENTITY(1,1) PRIMARY KEY,
  code             VARCHAR(20)   NOT NULL UNIQUE,
  organization_id  INT           NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  donation_id      INT           NULL REFERENCES donations(id),
  donor_user_id    INT           NULL REFERENCES users(id),
  donor_name       NVARCHAR(80)  NOT NULL,
  recipient_name   NVARCHAR(80)  NOT NULL,
  blood_type       VARCHAR(3)    NOT NULL REFERENCES blood_types(code),
  units            TINYINT       NOT NULL DEFAULT 1 CHECK (units BETWEEN 1 AND 20),
  donation_date    DATE          NOT NULL,
  status           VARCHAR(20)   NOT NULL DEFAULT 'Pending verification'
                   CHECK (status IN ('Pending verification','Verified')),
  notes            NVARCHAR(300) NULL,
  verified_by      INT           NULL REFERENCES users(id),
  verified_at      DATETIME2     NULL,
  created_at       DATETIME2     NOT NULL DEFAULT SYSDATETIME()
);
CREATE UNIQUE INDEX uq_dv_donation ON donation_verifications(donation_id) WHERE donation_id IS NOT NULL;
CREATE INDEX idx_dv_org_date ON donation_verifications(organization_id, donation_date);

CREATE TABLE blood_inventory (
  organization_id  INT        NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  blood_type       VARCHAR(3) NOT NULL REFERENCES blood_types(code),
  units            SMALLINT   NOT NULL DEFAULT 0  CHECK (units >= 0),
  min_target       SMALLINT   NOT NULL DEFAULT 15,
  critical_level   SMALLINT   NOT NULL DEFAULT 8,
  updated_at       DATETIME2  NOT NULL DEFAULT SYSDATETIME(),
  PRIMARY KEY (organization_id, blood_type)
);

/* ===================== HALLS & BOOKINGS ===================== */
CREATE TABLE halls (
  id             INT IDENTITY(1,1) PRIMARY KEY,
  name           NVARCHAR(120) NOT NULL,
  city_id        SMALLINT      NOT NULL REFERENCES cities(id),
  entity_type    VARCHAR(25)   NOT NULL
                 CHECK (entity_type IN ('University','Community center','Private institution','Government institution')),
  location_text  NVARCHAR(120) NULL,
  capacity       SMALLINT      NOT NULL CHECK (capacity > 0),
  price_jod      DECIMAL(8,2)  NOT NULL CHECK (price_jod >= 0),
  rating         DECIMAL(2,1)  NULL CHECK (rating BETWEEN 0 AND 5),
  tag            NVARCHAR(40)  NULL,
  image_url      NVARCHAR(255) NULL,
  description    NVARCHAR(500) NULL,
  is_active      BIT           NOT NULL DEFAULT 1,
  created_at     DATETIME2     NOT NULL DEFAULT SYSDATETIME()
);
CREATE INDEX idx_hall_filter ON halls(city_id, capacity);

CREATE TABLE hall_event_types (
  hall_id        INT     NOT NULL REFERENCES halls(id) ON DELETE CASCADE,
  event_type_id  TINYINT NOT NULL REFERENCES event_types(id) ON DELETE CASCADE,
  PRIMARY KEY (hall_id, event_type_id)
);

CREATE TABLE hall_features (
  hall_id  INT          NOT NULL REFERENCES halls(id) ON DELETE CASCADE,
  feature  NVARCHAR(60) NOT NULL,
  PRIMARY KEY (hall_id, feature)
);

CREATE TABLE hall_bookings (
  id                 INT IDENTITY(1,1) PRIMARY KEY,
  code               VARCHAR(20)    NOT NULL UNIQUE,
  hall_id            INT            NOT NULL REFERENCES halls(id),
  requested_by       INT            NOT NULL REFERENCES users(id),
  organization_id    INT            NULL REFERENCES organizations(id),
  organization_name  NVARCHAR(120)  NOT NULL,
  contact_name       NVARCHAR(80)   NOT NULL,
  contact_email      NVARCHAR(120)  NOT NULL,
  contact_phone      VARCHAR(20)    NOT NULL,
  event_type_id      TINYINT        NOT NULL REFERENCES event_types(id),
  event_date         DATE           NOT NULL,
  event_time         NVARCHAR(30)   NOT NULL,     -- Morning / Evening / All day
  attendees          SMALLINT       NOT NULL CHECK (attendees >= 1),
  fee_jod            DECIMAL(8,2)   NOT NULL,
  description        NVARCHAR(1000) NOT NULL,
  status             VARCHAR(20)    NOT NULL DEFAULT 'Pending approval'
                     CHECK (status IN ('Pending approval','Approved','Paid','Completed','Rejected')),
  admin_note         NVARCHAR(500)  NULL,
  reviewed_by        INT            NULL REFERENCES users(id),
  created_at         DATETIME2      NOT NULL DEFAULT SYSDATETIME(),
  updated_at         DATETIME2      NOT NULL DEFAULT SYSDATETIME()
);
CREATE INDEX idx_hb_status    ON hall_bookings(status);
CREATE INDEX idx_hb_hall_date ON hall_bookings(hall_id, event_date);

CREATE TABLE hall_booking_documents (
  id           INT IDENTITY(1,1) PRIMARY KEY,
  booking_id   INT           NOT NULL REFERENCES hall_bookings(id) ON DELETE CASCADE,
  doc_type     VARCHAR(20)   NOT NULL
               CHECK (doc_type IN ('official_letter','event_plan','organization_proof')),
  file_name    NVARCHAR(160) NOT NULL,
  file_path    NVARCHAR(255) NOT NULL,
  uploaded_at  DATETIME2     NOT NULL DEFAULT SYSDATETIME(),
  CONSTRAINT uq_hbd_type UNIQUE (booking_id, doc_type)
);

CREATE TABLE hall_booking_status_history (
  id          INT IDENTITY(1,1) PRIMARY KEY,
  booking_id  INT           NOT NULL REFERENCES hall_bookings(id) ON DELETE CASCADE,
  status      VARCHAR(20)   NOT NULL
              CHECK (status IN ('Pending approval','Approved','Paid','Completed','Rejected')),
  note        NVARCHAR(500) NULL,
  changed_by  INT           NULL REFERENCES users(id),
  changed_at  DATETIME2     NOT NULL DEFAULT SYSDATETIME()
);
CREATE INDEX idx_hbh_booking ON hall_booking_status_history(booking_id, changed_at);

/* ===================== ADVERTISEMENTS ===================== */
CREATE TABLE advertisements (
  id                INT IDENTITY(1,1) PRIMARY KEY,
  code              VARCHAR(20)    NOT NULL UNIQUE,
  organization_id   INT            NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  title             NVARCHAR(120)  NOT NULL,
  department_id     TINYINT        NOT NULL REFERENCES ad_departments(id),
  category_id       TINYINT        NOT NULL REFERENCES ad_categories(id),
  badge             NVARCHAR(20)   NULL,
  description       NVARCHAR(1000) NOT NULL,
  event_date        DATE           NULL,
  start_time        TIME(0)        NULL,
  end_time          TIME(0)        NULL,
  location_text     NVARCHAR(120)  NULL,
  phone             VARCHAR(20)    NULL,
  booking_required  BIT            NOT NULL DEFAULT 0,
  plan_code         VARCHAR(20)    NOT NULL REFERENCES ad_plans(code),
  start_date        DATE           NOT NULL,
  end_date          DATE           NOT NULL,
  fee_jod           DECIMAL(8,2)   NOT NULL,
  vat_jod           DECIMAL(8,2)   NOT NULL,
  total_jod         DECIMAL(8,2)   NOT NULL,
  views             INT            NOT NULL DEFAULT 0,
  is_cancelled      BIT            NOT NULL DEFAULT 0,
  created_at        DATETIME2      NOT NULL DEFAULT SYSDATETIME(),
  CONSTRAINT chk_ad_window CHECK (end_date >= start_date),
  CONSTRAINT chk_ad_times  CHECK (start_time IS NULL OR end_time IS NULL OR end_time > start_time)
);
CREATE INDEX idx_ad_window ON advertisements(start_date, end_date);

/* ===================== PAYMENTS ===================== */
CREATE TABLE payments (
  id                INT IDENTITY(1,1) PRIMARY KEY,
  hall_booking_id   INT           NULL REFERENCES hall_bookings(id),
  advertisement_id  INT           NULL REFERENCES advertisements(id),
  paid_by           INT           NOT NULL REFERENCES users(id),
  method            VARCHAR(10)   NOT NULL CHECK (method IN ('Bank card','E-wallet')),
  amount_jod        DECIMAL(10,2) NOT NULL CHECK (amount_jod > 0),
  receipt_number    VARCHAR(30)   NOT NULL UNIQUE,
  paid_at           DATETIME2     NOT NULL DEFAULT SYSDATETIME(),
  CONSTRAINT chk_pay_target CHECK (
    (hall_booking_id IS NOT NULL AND advertisement_id IS NULL) OR
    (hall_booking_id IS NULL AND advertisement_id IS NOT NULL))
);
CREATE UNIQUE INDEX uq_pay_booking ON payments(hall_booking_id)  WHERE hall_booking_id  IS NOT NULL;
CREATE UNIQUE INDEX uq_pay_ad      ON payments(advertisement_id) WHERE advertisement_id IS NOT NULL;

/* ===================== REPORTS & ADMIN LOG ===================== */
CREATE TABLE reports (
  id              INT IDENTITY(1,1) PRIMARY KEY,
  code            VARCHAR(20)    NOT NULL UNIQUE,
  reporter_id     INT            NULL REFERENCES users(id),
  reporter_name   NVARCHAR(60)   NOT NULL,
  reporter_email  NVARCHAR(80)   NOT NULL,
  reporter_role   VARCHAR(12)    NOT NULL CHECK (reporter_role IN ('Donor','Hospital','Organization','Other')),
  category        VARCHAR(25)    NOT NULL CHECK (category IN ('Technical issue','Donor complaint',
                    'Inappropriate content','Booking issue','Hospital issue','Data correction')),
  related_to      NVARCHAR(80)   NULL,
  title           NVARCHAR(90)   NOT NULL,
  body            NVARCHAR(1000) NOT NULL,
  priority        VARCHAR(6)     NOT NULL DEFAULT 'medium' CHECK (priority IN ('low','medium','high')),
  status          VARCHAR(10)    NOT NULL DEFAULT 'New' CHECK (status IN ('New','In review','Resolved')),
  is_read         BIT            NOT NULL DEFAULT 0,
  admin_response  NVARCHAR(1000) NULL,
  handled_by      INT            NULL REFERENCES users(id),
  created_at      DATETIME2      NOT NULL DEFAULT SYSDATETIME(),
  resolved_at     DATETIME2      NULL
);
CREATE INDEX idx_rep_status ON reports(status, priority);

CREATE TABLE report_attachments (
  id           INT IDENTITY(1,1) PRIMARY KEY,
  report_id    INT           NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
  file_name    NVARCHAR(160) NOT NULL,
  file_path    NVARCHAR(255) NOT NULL,
  mime_type    VARCHAR(80)   NULL,
  uploaded_at  DATETIME2     NOT NULL DEFAULT SYSDATETIME()
);

CREATE TABLE admin_activity_log (
  id           BIGINT IDENTITY(1,1) PRIMARY KEY,
  admin_id     INT           NULL REFERENCES users(id),
  action       VARCHAR(40)   NOT NULL,
  entity_type  VARCHAR(15)   NOT NULL
               CHECK (entity_type IN ('organization','hall_booking','report','advertisement','user')),
  entity_id    INT           NOT NULL,
  description  NVARCHAR(255) NOT NULL,
  created_at   DATETIME2     NOT NULL DEFAULT SYSDATETIME()
);
CREATE INDEX idx_log_created ON admin_activity_log(created_at);
GO

/* ===================== VIEWS ===================== */
CREATE VIEW v_advertisement_status AS
SELECT a.id, a.code, a.organization_id, a.title, a.plan_code, a.start_date, a.end_date, a.views,
       CASE
         WHEN a.is_cancelled = 1                     THEN 'Stopped'
         WHEN a.start_date > CAST(GETDATE() AS DATE) THEN 'Scheduled'
         WHEN a.end_date   < CAST(GETDATE() AS DATE) THEN 'Expired'
         ELSE 'Active'
       END AS status
FROM advertisements a;
GO

CREATE VIEW v_low_stock AS
SELECT i.organization_id, o.name AS organization_name, i.blood_type, i.units, i.min_target,
       CASE WHEN i.units < i.critical_level THEN 'critical' ELSE 'low' END AS level
FROM blood_inventory i
JOIN organizations o ON o.id = i.organization_id
WHERE i.units < i.min_target;
GO

CREATE VIEW v_donor_search AS
SELECT u.id AS donor_id, u.full_name, u.email, u.phone,
       c.name AS city, d.area, d.blood_type, d.is_available,
       d.latitude, d.longitude, d.location_mode, d.last_donation_date
FROM users u
JOIN donor_profiles d ON d.user_id = u.id
LEFT JOIN cities c    ON c.id = u.city_id
WHERE u.is_active = 1 AND u.role = 'donor';
GO

/* ===================== SEED LOOKUP DATA ===================== */
INSERT INTO cities (name) VALUES
 (N'Irbid'),(N'Amman'),(N'Zarqa'),(N'Aqaba'),(N'Salt'),(N'Madaba'),(N'Jerash'),
 (N'Ajloun'),(N'Mafraq'),(N'Karak'),(N'Tafilah'),(N'Ma''an'),(N'Other');

INSERT INTO blood_types (code) VALUES ('A+'),('A-'),('B+'),('B-'),('AB+'),('AB-'),('O+'),('O-');

INSERT INTO blood_compatibility (donor_type, recipient_type) VALUES
 ('O-','O-'),('O-','O+'),('O-','A-'),('O-','A+'),('O-','B-'),('O-','B+'),('O-','AB-'),('O-','AB+'),
 ('O+','O+'),('O+','A+'),('O+','B+'),('O+','AB+'),
 ('A-','A-'),('A-','A+'),('A-','AB-'),('A-','AB+'),
 ('A+','A+'),('A+','AB+'),
 ('B-','B-'),('B-','B+'),('B-','AB-'),('B-','AB+'),
 ('B+','B+'),('B+','AB+'),
 ('AB-','AB-'),('AB-','AB+'),
 ('AB+','AB+');

INSERT INTO event_types (name) VALUES (N'Conference'),(N'Initiative'),(N'Workshop'),(N'Training');

INSERT INTO ad_plans (code, name, duration_days, price_jod, perks) VALUES
 ('basic',    N'Basic',     7, 25.00, N'["Listed on the public ads page","Standard placement","7 days of visibility"]'),
 ('featured', N'Featured', 14, 50.00, N'["Highlighted card with badge","Priority placement","14 days of visibility"]'),
 ('premium',  N'Premium',  30, 90.00, N'["Top banner spot on the ads page","Featured badge + priority","30 days of visibility"]');

INSERT INTO ad_departments (name) VALUES
 (N'Orthopedics'),(N'Cardiology'),(N'Pediatrics'),(N'Internal medicine'),(N'Dermatology'),
 (N'Ophthalmology'),(N'Dental'),(N'Obstetrics & gynecology'),(N'Neurology'),(N'Blood bank'),(N'General / multiple');

INSERT INTO ad_categories (name, color, icon) VALUES
 (N'Free consultation day', '#13895f', 'stethoscope'),
 (N'Health screening',      '#3a72c9', 'pulse'),
 (N'Discounted service',    '#bd7c12', 'tag'),
 (N'Awareness campaign',    '#7a4cc2', 'megaphone'),
 (N'Blood donation drive',  '#d41d3d', 'drop'),
 (N'New service / clinic',  '#0f7f8f', 'spark');
GO