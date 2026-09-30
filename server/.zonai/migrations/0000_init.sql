CREATE TABLE "assignments" (
  "id" TEXT PRIMARY KEY,
  "owner_id" TEXT NOT NULL,
  "course_id" TEXT NOT NULL,
  "title" TEXT NOT NULL,
  "description" TEXT NOT NULL,
  "rubric_document" TEXT NOT NULL,
  "source_rubric_id" TEXT,
  "due_on" INTEGER,
  "points_possible" REAL NOT NULL,
  "closed" INTEGER NOT NULL,
  "created_on" INTEGER NOT NULL,
  "rev" INTEGER NOT NULL,
  "created_at" INTEGER NOT NULL,
  "updated_at" INTEGER NOT NULL,
  "deleted_at" INTEGER
);

CREATE TABLE "comment_snippets" (
  "id" TEXT PRIMARY KEY,
  "owner_id" TEXT NOT NULL,
  "body" TEXT NOT NULL,
  "category" TEXT NOT NULL,
  "use_count" INTEGER NOT NULL,
  "rev" INTEGER NOT NULL,
  "created_at" INTEGER NOT NULL,
  "updated_at" INTEGER NOT NULL,
  "deleted_at" INTEGER
);

CREATE TABLE "courses" (
  "id" TEXT PRIMARY KEY,
  "owner_id" TEXT NOT NULL,
  "name" TEXT NOT NULL,
  "section" TEXT NOT NULL,
  "term" TEXT NOT NULL,
  "archived" INTEGER NOT NULL,
  "created_on" INTEGER NOT NULL,
  "rev" INTEGER NOT NULL,
  "created_at" INTEGER NOT NULL,
  "updated_at" INTEGER NOT NULL,
  "deleted_at" INTEGER
);

CREATE TABLE "evaluations" (
  "id" TEXT PRIMARY KEY,
  "owner_id" TEXT NOT NULL,
  "assignment_id" TEXT NOT NULL,
  "student_id" TEXT NOT NULL,
  "status" TEXT NOT NULL,
  "document" TEXT NOT NULL,
  "updated_on" INTEGER NOT NULL,
  "rev" INTEGER NOT NULL,
  "created_at" INTEGER NOT NULL,
  "updated_at" INTEGER NOT NULL,
  "deleted_at" INTEGER
);

CREATE TABLE "rubrics" (
  "id" TEXT PRIMARY KEY,
  "owner_id" TEXT NOT NULL,
  "title" TEXT NOT NULL,
  "subject" TEXT NOT NULL,
  "is_template" INTEGER NOT NULL,
  "archived" INTEGER NOT NULL,
  "document" TEXT NOT NULL,
  "created_on" INTEGER NOT NULL,
  "rev" INTEGER NOT NULL,
  "created_at" INTEGER NOT NULL,
  "updated_at" INTEGER NOT NULL,
  "deleted_at" INTEGER
);

CREATE TABLE "students" (
  "id" TEXT PRIMARY KEY,
  "owner_id" TEXT NOT NULL,
  "course_id" TEXT NOT NULL,
  "first_name" TEXT NOT NULL,
  "last_name" TEXT NOT NULL,
  "student_number" TEXT NOT NULL,
  "email" TEXT NOT NULL,
  "notes" TEXT NOT NULL,
  "archived" INTEGER NOT NULL,
  "rev" INTEGER NOT NULL,
  "created_at" INTEGER NOT NULL,
  "updated_at" INTEGER NOT NULL,
  "deleted_at" INTEGER
);

CREATE TABLE "users" (
  "id" TEXT PRIMARY KEY,
  "email" TEXT NOT NULL,
  "is_verified" INTEGER NOT NULL,
  "password" TEXT NOT NULL,
  "created_at" INTEGER NOT NULL,
  "updated_at" INTEGER
);

CREATE UNIQUE INDEX "users.id_unique" ON "users" ("id");