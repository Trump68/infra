# SYSTEM ARCHITECTURE DESCRIPTION
## Information System "Farmadoc"

**Version:** 1.0
**Date:** 2026-02-18
**Status:** Draft
**Based on:** Technical Requirements for the "Farmadoc" Information System

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Abbreviations and Definitions](#2-abbreviations-and-definitions)
3. [System Overview](#3-system-overview)
4. [Architecture Principles](#4-architecture-principles)
5. [High-Level Architecture](#5-high-level-architecture)
6. [Module Descriptions](#6-module-descriptions)
   - 6.1 [User Web Interface](#61-user-web-interface)
   - 6.2 [API Gateway](#62-api-gateway)
   - 6.3 [Authentication and Authorization Service](#63-authentication-and-authorization-service)
   - 6.4 [RAG Module (Retrieval-Augmented Generation)](#64-rag-module-retrieval-augmented-generation)
   - 6.5 [Vector Database](#65-vector-database)
   - 6.6 [AI Agent Module](#66-ai-agent-module)
   - 6.7 [Document Parsing and Markup Module](#67-document-parsing-and-markup-module)
   - 6.8 [OCR Module](#68-ocr-module)
   - 6.9 [Translation Module](#69-translation-module)
   - 6.10 [Report Generation Module](#610-report-generation-module)
   - 6.11 [Secure Web Search Module](#611-secure-web-search-module)
   - 6.12 [Plugin Management Subsystem](#612-plugin-management-subsystem)
7. [Technology Stack](#7-technology-stack)
   - 7.1 [Infrastructure and Platform](#71-infrastructure-and-platform)
   - 7.2 [Backend and AI Frameworks](#72-backend-and-ai-frameworks)
   - 7.3 [LLM and Embeddings](#73-llm-and-embeddings)
   - 7.4 [Data Storage](#74-data-storage)
   - 7.5 [Security Technologies](#75-security-technologies)
   - 7.6 [Document Processing](#76-document-processing)
   - 7.7 [Monitoring and Logging](#77-monitoring-and-logging)
8. [Security Architecture](#8-security-architecture)
9. [Implementation Queues](#9-implementation-queues)
10. [Deployment Architecture](#10-deployment-architecture)

---

## 1. Introduction

This document describes the software architecture of the **"Farmadoc"** Information System developed for FSBI "SCEEMP" of the Ministry of Health of the Russian Federation. It defines the structural decomposition of the system into modules, the interaction between components, the technologies used, and the security model.

The target audience of this document is:
- software architects and developers;
- technical project managers;
- information security specialists;
- infrastructure and operations engineers.

The document is developed on the basis of the Technical Requirements (TR) for the "Farmadoc" Information System and is intended to be used as the primary reference during system design, implementation, testing, and maintenance.

---

## 2. Abbreviations and Definitions

| Abbreviation | Definition |
|---|---|
| API | Application Programming Interface |
| BLM | Big Language Model (LLM) |
| DOCX | Microsoft Word document format |
| GOST | Russian State Standard |
| ICH | International Council for Harmonisation |
| LLM | Large Language Model |
| MFA | Multi-Factor Authentication |
| NLP | Natural Language Processing |
| OCR | Optical Character Recognition |
| RAG | Retrieval-Augmented Generation |
| RBAC | Role-Based Access Control |
| SIEM | Security Information and Event Management |
| SSO | Single Sign-On |
| TLS | Transport Layer Security |
| VPN | Virtual Private Network |
| WAF | Web Application Firewall |
| RMP | Risk Management Plan (RUP/PUR) |

---

## 3. System Overview

"Farmadoc" is an intelligent document processing system designed to automate the search, analysis, comparison, and translation of pharmaceutical documents. The system applies Large Language Models (LLMs) and the Retrieval-Augmented Generation (RAG) paradigm to support regulatory experts, pharmacists, and quality assurance specialists in their daily work.

**Primary use cases:**
- Checking pharmaceutical instructions (SmPC, PIL) for compliance with regulatory requirements (Ministry of Health, EEC, ICH).
- Comparing documents (two or more versions, reference vs. proposed).
- Semantic search in a local document repository.
- Translating pharmaceutical documents while preserving regulatory terminology.
- OCR processing of scanned labels and packaging images.
- Generating structured reports in DOCX format.
- Secure, filtered internet search on approved external resources (EMA, FDA, WHO, etc.).

**Target organization:** FSBI "SCEEMP" of the Ministry of Health of the Russian Federation; also applicable to pharmaceutical companies and regulatory bodies.

---

## 4. Architecture Principles

The system is built on the following core architectural principles:

| Principle | Description |
|---|---|
| **Modularity** | Each functional area is encapsulated in an independent module/service. New capabilities are added as plugins without modifying the core. |
| **Security by Default** | Every component enforces authentication, authorization, and encryption. No data leaves the trusted boundary without explicit authorization. |
| **Zero Trust** | Each service authenticates requests independently, even within the internal network. |
| **Scalability** | Horizontal scaling via containerization (Docker/Kubernetes). Load balancing at the API Gateway level. |
| **Observability** | All system events and user actions are logged. SIEM integration provides centralized audit and alerting. |
| **Isolation** | AI agents execute in sandboxed Docker containers with network and filesystem restrictions. |
| **Data Minimization** | Personal and sensitive data is anonymized/masked before passing to LLM processing (using Microsoft Presidio or equivalent). |

---

## 5. High-Level Architecture

The system follows a **layered microservices architecture**. The diagram below illustrates the main components and their interaction flows:

```
┌──────────────────────────────────────────────────────────┐
│                 Client Layer (Browser)                    │
│         Web Interface  (React / Vue.js SPA)               │
│         Runs on Windows 10 workstations (domain network)  │
└──────────────────┬───────────────────────────────────────┘
                   │  HTTPS / TLS 1.3
                   ▼
┌──────────────────────────────────────────────────────────┐
│                  API Gateway (Kong)                        │
│  - Authentication enforcement (JWT / Keycloak token)      │
│  - RBAC authorization                                     │
│  - Rate limiting (100 req/min per user)                   │
│  - WAF / DDoS protection                                  │
│  - Request logging (IP, user, timestamp, type)            │
└──────┬────────┬────────┬──────────┬──────────┬───────────┘
       │        │        │          │          │
       ▼        ▼        ▼          ▼          ▼
  ┌────────┐ ┌──────┐ ┌──────┐ ┌────────┐ ┌────────────┐
  │ Auth   │ │ RAG  │ │Agent │ │ OCR    │ │ Report     │
  │Service │ │Module│ │Module│ │Module  │ │ Generator  │
  │Keycloak│ │      │ │      │ │        │ │ (DOCX)     │
  └────────┘ └──┬───┘ └──┬───┘ └────────┘ └────────────┘
                │        │
       ┌────────┘        └─────────────┐
       ▼                               ▼
┌─────────────────┐          ┌───────────────────┐
│  Vector Database│          │  External Sources  │
│ (Redis/Pinecone)│          │  (EMA, FDA, WHO)   │
│  AES-256 / GOST │          │  (allowlisted URLs)│
└────────┬────────┘          └───────────────────┘
         │
         ▼
┌─────────────────┐
│  LLM / Generator│
│ (local / trusted│
│  cloud)         │
└─────────────────┘
```

All inter-service communication is encrypted via **TLS 1.3**. Sensitive data stored at rest is encrypted using **AES-256** or **GOST R 34.12-2015**. Encryption key management is handled by **HashiCorp Vault** with 90-day rotation policy.

---

## 6. Module Descriptions

### 6.1 User Web Interface

**Purpose:** Provides a browser-based graphical interface for all user interactions with the system.

**Key functions:**
- Upload documents (DOCX, PDF, JPEG, PNG) for analysis or comparison.
- Configure analysis parameters (document type, comparison target, search scope).
- Initiate semantic search queries in the local document repository.
- View analysis results, difference reports, and generated recommendations.
- Visual markup editor — allows manual adjustment of document segmentation boundaries produced by the parser.
- Download results as DOCX reports.
- Select report templates (pre-loaded by administrator).
- Manage document repository (add/remove documents — authorized users only).

**Technical characteristics:**
- Single-Page Application (SPA) running in a web browser.
- Interface language: **Russian** (all UI labels, forms, and messages).
- Accessible from domain-joined Windows 10 workstations.
- Communicates with backend exclusively via API Gateway over HTTPS/TLS 1.3.

---

### 6.2 API Gateway

**Purpose:** Acts as the single entry point for all client requests, enforcing security policies and routing traffic to backend services.

**Key functions:**
- **Authentication enforcement:** Validates JWT tokens issued by the Authentication Service (Keycloak).
- **Authorization (RBAC):** Verifies user roles and permissions before forwarding requests.
- **Rate limiting:** Enforces a maximum of 100 requests per minute per authenticated user.
- **DDoS and WAF protection:** Integrated with the organization's WAF to filter malicious traffic.
- **Request routing:** Routes requests to the appropriate backend microservice.
- **Audit logging:** Records all requests with metadata — IP address, user identity, timestamp, request type, and response status.

**Technology:** Kong API Gateway (or equivalent open-source alternative).

---

### 6.3 Authentication and Authorization Service

**Purpose:** Manages user identity, session lifecycle, and role-based access control for all system components.

**Key functions:**
- Integration with the organization's existing identity infrastructure via **Keycloak**.
- Support for **Single Sign-On (SSO)** within the domain.
- Mandatory **Multi-Factor Authentication (MFA)** for all users.
- Role model (RBAC): roles and permission matrices are defined during technical design, covering at minimum — Administrator, Expert, Analyst, Read-Only User.
- Issues and validates JWT tokens consumed by the API Gateway.
- Provides authorization context to the Vector Database retriever (access-aware search).

**Technology:** Keycloak, OpenID Connect, OAuth 2.0, JWT.

---

### 6.4 RAG Module (Retrieval-Augmented Generation)

**Purpose:** The core AI intelligence module. Combines semantic search (Retriever) with LLM-based response generation (Generator) to answer user queries grounded in the document repository.

**Sub-components:**

#### 6.4.1 Retriever
- Executes semantic similarity search against the Vector Database using the query embedding.
- Applies **RBAC filtering**: only documents accessible to the requesting user are returned. Access denial events are logged.
- Retrieves top-K relevant document chunks and passes them as context to the Generator.

#### 6.4.2 Generator
- Receives retrieved context from the Retriever and additional data from AI agents.
- Uses an **LLM** (Large Language Model) deployed **locally on organization servers** or in a **trusted private cloud** to generate structured, context-aware responses.
- Personal and sensitive data is automatically anonymized before being passed to the model (via Presidio middleware).

**Key capabilities:**
- Semantic search in the local document corpus.
- Regulatory compliance analysis of pharmaceutical instructions.
- Document comparison (semantic and formal differences).
- Q&A grounded in internal documents.

---

### 6.5 Vector Database

**Purpose:** Stores encrypted vector embeddings of all indexed documents and supports high-speed semantic similarity search.

**Key functions:**
- Stores vector representations (embeddings) of document chunks produced during indexing.
- Supports semantic similarity queries (k-nearest-neighbor / approximate nearest-neighbor search).
- Enforces logical separation of three document classes:
  | Class | Examples |
  |---|---|
  | **Regulatory** | Standards, guidelines, pharmacopoeia articles |
  | **Working** | Instructions (SmPC/PIL), RMPs, NQDs, packaging images |
  | **External cache** | Results of approved web searches (TTL: 24 hours) |
- Encryption at rest: **AES-256** or **GOST R 34.12-2015**.
- Data transfer: **TLS 1.3**.
- Encryption keys stored in **HashiCorp Vault** with **90-day rotation**.
- Personal data is masked using **Microsoft Presidio** prior to indexing.

**Technology:** Redis (with vector search extensions) or Pinecone, or equivalent.

---

### 6.6 AI Agent Module

**Purpose:** Provides a pluggable framework for autonomous AI agents that handle specialized processing scenarios as isolated, composable units.

**Key functions:**
- Implements specialized processing pipelines: document comparison, internet search, template filling, compliance verification, RMP analysis.
- Each agent runs in an **isolated Docker container** with:
  - Restricted network access (allowlisted domains only).
  - Read-only or scoped filesystem access.
  - CPU/memory resource limits.
- Agents are **pluggable**: new agents can be added without modifying the system core, using a standard plugin interface.
- New agents undergo **security verification** before activation (malware scan via ClamAV or equivalent).
- Agent interaction with the RAG module: agents can retrieve context from the Vector DB and pass additional data to the Generator.

**Framework:** LangChain, AutoGen, or equivalent agent orchestration framework.

**Built-in agents (Queue 1):**
| Agent | Responsibility |
|---|---|
| Compliance Agent | Checks SmPC/PIL structure and content against regulatory requirements |
| Comparison Agent | Performs semantic and formal diff of two or more documents |
| Anonymization Middleware | Masks PII before any LLM call |
| Markup Agent | Segments documents into logical blocks for LLM processing |

**Additional agents (Queue 2):**
| Agent | Responsibility |
|---|---|
| Web Search Agent | Fetches and caches approved external sources |
| Translation Agent | Translates pharmaceutical documents preserving structure |
| OCR Pre-processing Agent | Extracts text from images/scans before indexing |

---

### 6.7 Document Parsing and Markup Module

**Purpose:** Automatically segments incoming documents into logical blocks (sections, paragraphs, tables) to enable efficient LLM processing.

**Key functions:**
- Parses documents in DOCX and PDF formats.
- Identifies and labels structural elements: headings, sections, subsections, tables, figures, footnotes.
- Produces a structured representation suitable for chunking and embedding.
- Exposes a **visual markup editor** in the web interface, allowing authorized users to manually adjust segment boundaries.
- Integrates with the indexing pipeline to populate the Vector Database.

---

### 6.8 OCR Module

**Purpose:** Extracts machine-readable text from scanned documents, images, and PDF files that do not contain selectable text.

**Key functions:**
- Accepts input formats: **PDF** (image-based), **JPEG**, **PNG**.
- Performs text recognition on pharmaceutical documents including packaging images, labels, and scanned regulatory forms.
- Outputs plain text and structured text blocks for downstream processing by the Parsing Module.
- Recognized text is indexed in the Vector Database for semantic search.

**Technology:** Tesseract OCR, PaddleOCR, or equivalent; integrated as an AI agent in the Agent Module.

*Note: OCR is part of the **second implementation queue**.*

---

### 6.9 Translation Module

**Purpose:** Provides automated translation of pharmaceutical documents from foreign languages into Russian, preserving document structure and regulatory terminology.

**Key functions:**
- Supports translation from major pharmaceutical document languages (English, German, French, etc.) into Russian.
- Uses a **locally deployed** or **trusted private cloud** LLM fine-tuned or prompted for pharmaceutical terminology.
- Preserves the **structural formatting** of the original document (sections, tables, headings).
- Outputs translated documents in **DOCX format** matching the original layout.
- Supports second-queue use case: bilingual comparison of RMPs (Russian and English versions).

*Note: Translation is part of the **second implementation queue**.*

---

### 6.10 Report Generation Module

**Purpose:** Produces structured, formatted output reports based on predefined templates provided by the Customer or developed by the Contractor.

**Key functions:**
- Generates reports in **DOCX format** from analysis results (compliance checks, comparisons, search results).
- Supports multiple report templates; administrators and authorized users can select the appropriate template.
- Template management: administrators can upload and manage template files via the web interface.
- Preserves formatting, structure, and branding requirements of the Customer.

**Technology:** python-docx (or equivalent library).

---

### 6.11 Secure Web Search Module

**Purpose:** Enables AI-assisted, controlled search of approved external pharmaceutical resources, with results cached locally.

**Key functions:**
- Searches only **allowlisted domains** configurable by the administrator (e.g., EMA, FDA, WHO, Roszdravnadzor).
- **Confidentiality filter:** queries containing sensitive or confidential information are blocked from external transmission and processed using only the internal document corpus.
- Retrieves data via **REST API** or **web scraping** depending on target resource availability.
- Results are cached in the Vector Database (TTL: **24 hours**).
- Integrates with the RAG module — cached external results are available for semantic retrieval alongside internal documents.
- Supports access to patent databases and international pharmaceutical registries.

*Note: Secure web search is part of the **second implementation queue**.*

---

### 6.12 Plugin Management Subsystem

**Purpose:** Provides a standardized interface for registering, verifying, and lifecycle-managing AI agent plugins without modifying the system core.

**Key functions:**
- Plugin registration API: accepts new agent plugins packaged as Docker images.
- **Security verification** of uploaded plugins before activation (static analysis, ClamAV antivirus scan).
- Lifecycle management: activate, deactivate, update, remove plugins.
- Isolation guarantees: each plugin runs in a dedicated container with enforced resource and network policies.
- Plugin catalog accessible to administrators via the web interface.

*Note: Plugin management UI is part of the **second implementation queue**.*

---

## 7. Technology Stack

### 7.1 Infrastructure and Platform

| Component | Technology | Notes |
|---|---|---|
| Server OS | Ubuntu 24.04 LTS | Production servers |
| Client OS | Windows 10 | Domain workstations |
| Containerization | Docker | All backend services |
| Container Orchestration | Kubernetes (or Docker Compose for smaller deployments) | Horizontal scaling |
| CI/CD | GitLab CI / Jenkins (to be agreed with Customer) | Automated build and deployment |
| Configuration Management | Customer's VCS with auto-build | Source code repository |
| VPN | WireGuard | Secure remote access |

---

### 7.2 Backend and AI Frameworks

| Component | Technology | Notes |
|---|---|---|
| Primary language | Python 3.11+ | Backend services, AI pipelines |
| AI Agent Framework | LangChain, AutoGen (or equivalent) | Agent orchestration |
| API Framework | FastAPI (or equivalent) | Internal service APIs |
| Frontend framework | React or Vue.js | SPA web interface |
| API Gateway | Kong (or equivalent) | Entry point, security enforcement |

---

### 7.3 LLM and Embeddings

| Component | Technology | Notes |
|---|---|---|
| Large Language Model | Locally deployed LLM (e.g., Mistral, Llama 3, GigaChat, YandexGPT) or trusted private cloud | Must be deployed within trusted boundary |
| Embedding Model | OpenAI Embeddings (self-hosted) or equivalent (e.g., E5, BGE, ruBERT) | Used for vector indexing |
| PII Anonymization | Microsoft Presidio (or equivalent) | Applied before every LLM call |

---

### 7.4 Data Storage

| Component | Technology | Notes |
|---|---|---|
| Vector Database | Redis (with RediSearch + vector module) or Pinecone | Semantic search storage |
| Relational Database | PostgreSQL (or equivalent) | User data, audit logs, metadata |
| Key Management | HashiCorp Vault | Encryption keys, secrets; 90-day rotation |
| File Storage | Local filesystem / S3-compatible storage | Document originals |

---

### 7.5 Security Technologies

| Component | Technology | Notes |
|---|---|---|
| Identity Provider | Keycloak | SSO, MFA, OAuth 2.0 / OIDC |
| Transport Encryption | TLS 1.3 | All inter-component communication |
| Data Encryption at Rest | AES-256 / GOST R 34.12-2015 | Vector DB, backups |
| Hash Algorithm | GOST R 34.11-2012 (Streebog) | Integrity checks |
| WAF | Organization WAF (existing) | DDoS protection, request filtering |
| Malware Scanning | ClamAV (or equivalent) | Plugin verification |
| PII Masking | Microsoft Presidio | Pre-LLM anonymization middleware |
| SIEM Integration | Via syslog / API | Centralized audit and alerting |
| MFA | TOTP / FIDO2 via Keycloak | Mandatory for all users |

---

### 7.6 Document Processing

| Component | Technology | Notes |
|---|---|---|
| DOCX generation | python-docx | Report generation module |
| DOCX parsing | python-docx, mammoth | Document ingestion |
| PDF parsing | PyMuPDF (fitz), pdfplumber | PDF text extraction |
| OCR | Tesseract OCR / PaddleOCR | Image and scanned document processing |
| Document chunking | LangChain text splitters, custom segmenter | Markup/parsing module |

---

### 7.7 Monitoring and Logging

| Component | Technology | Notes |
|---|---|---|
| Logging | ELK Stack (Elasticsearch + Logstash + Kibana) or equivalent | Centralized log management |
| Metrics | Prometheus + Grafana | System performance monitoring |
| SIEM | Customer SIEM (integration via syslog/API) | Security event management |
| Audit trail | Database audit table + log file | All user and system actions |

---

## 8. Security Architecture

### 8.1 Access Control Model

The system implements a **Role-Based Access Control (RBAC)** model. Roles are defined during technical design; the following preliminary roles are anticipated:

| Role | Description |
|---|---|
| Administrator | Full access: system configuration, user management, template and plugin management |
| Expert | Full document operations: upload, analyze, compare, translate, search, generate reports |
| Analyst | Read and search access, generate reports; cannot modify document repository |
| Read-Only User | View results and reports only |

All role assignments are managed via **Keycloak**. Authentication requires **MFA** for all users without exception.

---

### 8.2 Data Protection

| Layer | Mechanism |
|---|---|
| **In transit** | TLS 1.3 for all HTTP communication; WireGuard VPN for remote access |
| **At rest — vector DB** | AES-256 or GOST R 34.12-2015 |
| **At rest — backups** | Encrypted backups with the same standard |
| **Encryption keys** | HashiCorp Vault; rotation every 90 days |
| **PII before LLM** | Automatic anonymization via Presidio middleware |
| **Sensitive queries** | Blocked from external transmission; processed internally only |

---

### 8.3 AI Agent Isolation (Sandbox)

AI agents are executed in **isolated Docker containers** with the following constraints:

- **Network:** access only to an allowlisted set of internal services and external domains. All other outbound traffic is blocked.
- **Filesystem:** read-only or scoped mounts; no access to host filesystem or other containers.
- **Resources:** CPU and memory limits enforced via Docker cgroups.
- **Lifecycle:** containers are spun up per task and destroyed upon completion — no persistent agent state outside the Vector DB.
- **Plugin verification:** new agent Docker images are scanned for malware (ClamAV) and undergo policy compliance check before activation.

---

### 8.4 Audit and Logging

- All user actions (logins, document uploads, queries, report generation, role changes) are recorded in an immutable audit log.
- All API Gateway requests are logged: IP, user identity, timestamp, request type, HTTP status, latency.
- Access denial events (RBAC violations) are logged and trigger SIEM alerts.
- Logs are stored locally and forwarded to the Customer's SIEM system.
- Log retention period is defined during technical design in accordance with regulatory requirements.

---

### 8.5 Compliance

| Requirement | Mechanism |
|---|---|
| Federal Law No. 152-FZ (Personal Data) | PII anonymization, RBAC, encrypted storage, audit trail |
| GOST R 34.12-2015 (encryption) | Encryption of data at rest in vector DB and backups |
| GOST R 34.11-2012 (hashing) | Integrity verification |
| ISO/IEC 27001 (audit readiness) | Comprehensive logging, SIEM integration, formal access control |
| Roskomnadzor recommendations | Data processing policies, consent management |

---

## 9. Implementation Queues

The system is developed in two implementation queues as defined in the Technical Requirements.

### 9.1 Queue 1 — Core Functionality

| # | Module / Feature |
|---|---|
| 1 | User web interface (document upload, search UI, results viewer, markup editor) |
| 2 | API Gateway (Kong) with authentication, RBAC, rate limiting, logging |
| 3 | Authentication Service (Keycloak, MFA, SSO) |
| 4 | Vector Database — initialization, indexing pipeline, encryption |
| 5 | RAG Module — Retriever and Generator |
| 6 | AI Agent: Compliance Agent — regulatory check of SmPC/PIL |
| 7 | AI Agent: Comparison Agent — document comparison |
| 8 | Document Parsing and Markup Module |
| 9 | Report Generation Module (DOCX templates) |
| 10 | Anonymization Middleware (Presidio) |

---

### 9.2 Queue 2 — Extended Functionality

| # | Module / Feature |
|---|---|
| 1 | Secure Web Search Module (allowlisted external sources, caching) |
| 2 | Translation Module (pharmaceutical document translation, DOCX output) |
| 3 | OCR Module (PDF/image text extraction and indexing) |
| 4 | Plugin Management Subsystem (UI for registering and managing agent plugins) |
| 5 | Bilingual RMP comparison (Russian vs. English) |
| 6 | AI-generated RMP summary comparison with original |
| 7 | Cross-language search: internal Russian data vs. international sources (EMA, FDA) |

---

## 10. Deployment Architecture

### 10.1 Server Infrastructure

The system is deployed on servers provided by the Customer (FSBI "SCEEMP"). The following server roles are anticipated:

| Server Role | OS | Key Components |
|---|---|---|
| Application Server | Ubuntu 24.04 LTS | Docker, API Gateway, backend microservices |
| AI / LLM Server | Ubuntu 24.04 LTS | LLM runtime (GPU recommended), embedding model |
| Vector Database Server | Ubuntu 24.04 LTS | Redis / Pinecone instance |
| Database Server | Ubuntu 24.04 LTS | PostgreSQL, audit log storage |
| Key Management Server | Ubuntu 24.04 LTS | HashiCorp Vault |
| Backup Server | Ubuntu 24.04 LTS | Encrypted backups (RPO/RTO: max 4 hours data loss) |

*Exact hardware specifications (CPU, RAM, storage, GPU) are defined during technical design based on performance requirements.*

---

### 10.2 Network Topology

```
[Internet]
    |
[WAF] ──── [WireGuard VPN] ──── [Remote Users]
    |
[Firewall / DMZ]
    |
[Internal Domain Network]
    |
    ├── [Windows 10 Workstations] ── HTTPS ──► [API Gateway]
    |                                                |
    └── [Server Segment]                            |
         ├── API Gateway                ◄───────────┘
         ├── Auth Service (Keycloak)
         ├── App Services (Docker)
         ├── LLM / AI Server
         ├── Vector DB Server
         ├── PostgreSQL Server
         ├── HashiCorp Vault
         └── Backup Server
```

---

### 10.3 Reliability and Recovery

| Parameter | Target Value |
|---|---|
| Maximum Recovery Time (RTO) | 4 hours |
| Recovery Point Objective (RPO) | No data loss beyond 4 hours |
| Backup frequency | At minimum daily; incremental as appropriate |
| Backup encryption | AES-256 / GOST R 34.12-2015 |
| Failover | Hardware redundancy and service restart policies defined during technical design |
| Error handling | All user errors return informative messages; system returns to stable state without data corruption |

---

### 10.4 Scalability

- The system is designed to support a minimum of **100 concurrent users**.
- The API Gateway enforces per-user rate limits (100 req/min) and provides traffic shaping.
- Backend services are containerized and can be horizontally scaled by deploying additional container replicas.
- The Vector Database and LLM server are the primary performance bottlenecks; their sizing is addressed during technical design.

---

*End of document.*

---

**Document history:**

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | 2026-02-18 | — | Initial draft based on Technical Requirements v1.0 |
