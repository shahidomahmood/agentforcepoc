# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Salesforce DX project for an Agentforce proof-of-concept. Uses Salesforce API v64.0. Metadata is deployed directly to Salesforce orgs — there is no compilation step.

## Commands

### Testing
```bash
npm run test                    # Run all LWC Jest unit tests
npm run test:unit:watch         # Run tests in watch mode
npm run test:unit:debug         # Run tests in debug mode
npm run test:unit:coverage      # Generate coverage report

# Run tests for a single component
npx sfdx-lwc-jest --testPathPattern="componentName"
```

### Linting & Formatting
```bash
npm run lint              # ESLint on Aura and LWC JS files
npm run prettier          # Format all files (Apex, HTML, JS, JSON, YAML, XML)
npm run prettier:verify   # Verify formatting without writing changes
```

### Salesforce Deployment (via Salesforce CLI)
```bash
sf project deploy start --source-dir force-app   # Deploy metadata to default org
sf project retrieve start --source-dir force-app  # Pull latest metadata from org
sf org open                                        # Open the connected Salesforce org
```

### Scratch Org Workflow
```bash
sf org create scratch --definition-file config/project-scratch-def.json --alias my-scratch-org --set-default
sf project deploy start --source-dir force-app
sf org open
```

## Pre-commit Hook

Husky runs `npm run precommit` (lint-staged) on every commit. Staged files trigger:
- **Prettier** — all supported file types (Apex, HTML, JS, CSS, XML, JSON, YAML, Markdown)
- **ESLint** — Aura and LWC JavaScript files only
- **Jest** — `--bail --findRelatedTests --passWithNoTests` on any changed LWC file

If any check fails, the commit is blocked. Fix the reported issues and re-stage before retrying.

## Architecture

Metadata lives under `force-app/main/default/`:

- **`lwc/`** — Lightning Web Components (UI layer). Each component is a folder with `.html`, `.js`, `.css`, and a `.js-meta.xml` config file. Components communicate via properties, custom events, and the Lightning Message Service.
- **`classes/`** — Apex classes (server-side logic). Methods marked `@AuraEnabled` are callable from LWC via `@wire` adapters or imperative imports (`@salesforce/apex/ClassName.methodName`).
- **`objects/`** — Custom object definitions: fields, validation rules, relationships.
- **`aura/`** — Legacy Aura components. Do not add new components here; use LWC.
- **`flexipages/`** and **`layouts/`** — Page composition and record layouts.
- **`permissionsets/`** — Role-based access control definitions.
- **`triggers/`** — Apex triggers for object lifecycle events.

### LWC ↔ Apex Data Flow
LWC components fetch data from Apex either reactively (`@wire(apexMethod, { param })`) or imperatively (calling the imported method directly in JS). Test files live in `__tests__/` inside the component folder and are excluded from Salesforce deployments via `.forceignore`.

## Key Configuration

| File | Purpose |
|------|---------|
| `sfdx-project.json` | SFDX project config — package directories, API version (64.0), org login URL |
| `config/project-scratch-def.json` | Scratch org definition (Developer edition, Lightning Experience enabled) |
| `jest.config.js` | Jest config extending `@salesforce/sfdx-lwc-jest/config` |
| `eslint.config.js` | ESLint 9 flat config — separate rule sets for Aura, LWC, and Jest test files |
| `.prettierrc` | Prettier config; LWC HTML uses `lwc` parser, Aura/VF uses `html` parser |
| `.forceignore` | Excludes `__tests__/`, `jsconfig.json`, `.eslintrc.json`, and `package.xml` from deploys |
