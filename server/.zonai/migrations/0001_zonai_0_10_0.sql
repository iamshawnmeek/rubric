-- Existing rows, before the constraint that holds "users"."email" to lowercase().
-- Fails on a unique index if two rows differ only in what lowercase() removes: resolve those by hand first.
UPDATE "users" SET "email" = LOWER("email") WHERE "email" <> LOWER("email");

-- Requires foreign_keys = OFF (SQLite 12-step ALTER TABLE procedure).
-- The migrator disables them around the transaction; `PRAGMA
-- foreign_keys` inside one is silently a no-op.
CREATE TABLE "__new_users" (
  "id" TEXT PRIMARY KEY,
  "email" TEXT NOT NULL,
  "is_verified" INTEGER NOT NULL,
  "password" TEXT NOT NULL,
  "created_at" INTEGER NOT NULL,
  "updated_at" INTEGER,
  CONSTRAINT "users_email_lowercase" CHECK ("email" = LOWER("email"))
);
INSERT INTO "__new_users" ("id", "email", "is_verified", "password", "created_at", "updated_at") SELECT "id", "email", "is_verified", "password", "created_at", "updated_at" FROM "users";
DROP TABLE "users";
ALTER TABLE "__new_users" RENAME TO "users";
CREATE UNIQUE INDEX "users.id_unique" ON "users" ("id");
CREATE UNIQUE INDEX "users.email_unique" ON "users" ("email");