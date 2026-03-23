# Repository Setup & Initialization

Comprehensive command that handles both repository structure initialization and codebase analysis for Project AI Augmented Development.

## Content Guidelines

All created documentation and files must follow these principles:

### Conciseness Requirements
- **Keep descriptions short and to the point** - no verbose explanations
- **Focus on essential information only** - avoid redundant details  
- **Use direct language** - eliminate unnecessary words and phrases
- **Reference code directly** - use `file_path:line_number` format for specific implementations

### Code Documentation Standards
- **Self-documenting code preferred** - clear variable/function names over comments
- **Reference actual implementations** - point to specific code locations instead of generic descriptions
- **Include working examples** - verify all examples actually function
- **Current state focus** - document what exists, not what's planned

### File Structure
- **One concept per file** - keep files focused on single topics
- **Brief summaries only** - detailed information should reference code locations
- **Essential sections only** - omit empty or placeholder sections

## Process

The discovery process has two main phases:

### Phase 1: Repository Structure Initialization
1. **Check Current Directory:** Verify we're in a git repository root
2. **Initialize the project AI Structure:** Create AGENTS.md, CLAUDE.md, and ai-docs/ folder
3. **Create tasks Directory:** Initialize the temporary development workspace
4. **Create Standard Documentation Files:** Initialize all standard ai-docs files with templates

### Phase 2: Repository Analysis
1. **Architecture Analysis:** Understand overall system design and patterns
2. **Technology Stack Discovery:** Identify frameworks, libraries, and dependencies
3. **Communication Patterns Analysis:** Map APIs, messaging, and service interactions
4. **Database & Storage Analysis:** Document data architecture and storage patterns
5. **Docker & Kubernetes Analysis:** Understand containerization and orchestration
6. **Generate Documentation:** Create architecture.md and tech_stack.md

## AI Repository Structure Initialization

### AGENTS.md Template

**IMPORTANT**: This template must be populated with ACTUAL current repository state, not placeholder text.

```markdown
# AI Agent Repository Context

This file provides vendor-agnostic context for AI coding assistants based on the CURRENT STATE of this repository. It points to comprehensive documentation in the `ai-docs/` folder that reflects what has actually been implemented.

## 🔧 Repository Overview
- [ai-docs/README.md](ai-docs/README.md) - Current repository purpose, implemented functionality, and working features

## 🏗️ Architecture & Design  
- [ai-docs/ARCHITECTURE.md](ai-docs/ARCHITECTURE.md) - Current system architecture, implemented components, and their actual responsibilities
- [ai-docs/SCHEMA.md](ai-docs/SCHEMA.md) - Current external database schemas and repository entity definitions (no internal domain entities)

## 🔌 Interfaces
- [ai-docs/API.md](ai-docs/API.md) - Currently available external API endpoints and interfaces (no internal domain APIs)
- [ai-docs/INTEGRATIONS.md](ai-docs/INTEGRATIONS.md) - Currently integrated external services and working system connections

## 🧪 Development Practices
- [ai-docs/DEVELOPMENT.md](ai-docs/DEVELOPMENT.md) - Current coding standards, technology stack in use, and contribution guidelines
- [ai-docs/TESTING.md](ai-docs/TESTING.md) - Current testing strategy, existing test suites, and coverage status

---

*This documentation reflects the current implementation state and should be updated whenever features are added or modified.*
```

**Creation Instructions**:
1. **Analyze actual codebase** before creating AGENTS.md
2. **Document only implemented features** - do not include planned but unimplemented functionality
3. **Update descriptions** to reflect current state (e.g., "3 API endpoints implemented" instead of generic "API documentation")
4. **Remove or mark unavailable sections** if corresponding functionality doesn't exist yet
5. **Include tech design references** - if technical design documents exist, reference them in the Architecture & Design section

### CLAUDE.md Template

```markdown
@AGENTS.md
```

## Repository Analysis Framework

### 1. Architecture Analysis
- **Overall Architecture Pattern**: Identify if it's monolithic, microservices, serverless, or hybrid
- **Akka Actor System**: Map actor hierarchies, supervision strategies, and message flows
- **Go Service Architecture**: Identify service boundaries, goroutine patterns, and channel usage
- **Service Boundaries**: Map out distinct services/modules and their responsibilities
- **Data Flow**: Trace how data moves through the system, including actor message passing
- **Container Architecture**: Understand Docker image structure and multi-stage builds
- **Kubernetes Deployment**: Analyze deployment patterns, service mesh, and orchestration
- **Scalability Patterns**: Identify horizontal/vertical scaling approaches, Akka clustering, K8S HPA/VPA

### 2. Communication Patterns
- **HTTP/REST APIs**: Identify REST endpoints, API versions, authentication methods
- **gRPC Services**: Look for .proto files, service definitions, and client implementations
- **GraphQL**: Check for schema definitions, resolvers, and query structures
- **Akka HTTP**: Route definitions, directives, and marshalling/unmarshalling
- **Akka Streams**: Stream processing pipelines and backpressure handling
- **Go HTTP Servers**: Mux patterns, middleware, and handler implementations
- **Kubernetes Services**: ClusterIP, NodePort, LoadBalancer configurations
- **Service Mesh**: Istio, Linkerd configurations and traffic management
- **Internal Communication**: Actor messaging, Go channels, service-to-service communication

### 3. Caching Strategy
- **Redis**: Configuration, usage patterns, data structures used, Redis Operator deployments
- **Memcached**: Implementation details and use cases
- **Application-level Caching**: In-memory caches, CDN usage
- **Database Caching**: Query result caching, connection pooling
- **Cache Invalidation**: Strategies for cache consistency
- **Kubernetes ConfigMaps/Secrets**: Configuration management patterns

### 4. Message Queue & Event Systems
- **Apache Kafka**: Topics, partitions, consumer groups, producers, Kafka Operator
- **Amazon SQS/SNS**: Queue configurations, message patterns, AWS integration
- **RabbitMQ**: Exchanges, queues, routing keys, RabbitMQ Operator
- **Akka Streams Kafka**: Alpakka Kafka connectors and stream processing
- **Event Sourcing**: Event stores and replay mechanisms, Akka Persistence
- **Pub/Sub Patterns**: Publisher-subscriber implementations
- **AWS EKS Integration**: IAM roles, service accounts, and AWS services

### 5. Database Architecture
- **SQL Databases**: PostgreSQL, MySQL, SQL Server schemas and relationships
- **NoSQL Databases**: MongoDB, DynamoDB, Cassandra data models
- **Time-series Databases**: InfluxDB, TimescaleDB usage
- **Graph Databases**: Neo4j, Amazon Neptune implementations
- **Database Migrations**: Schema evolution strategies, init containers
- **Akka Persistence**: Event sourcing, snapshots, and journal configurations
- **Go Database Libraries**: GORM, sqlx, database/sql patterns
- **Database Operators**: PostgreSQL Operator, MongoDB Operator deployments

### 6. Third-party Libraries & Dependencies
- **Scala/Akka Ecosystem**: 
  - Akka HTTP, Akka Streams, Akka Persistence, Akka Cluster
  - Slick, Doobie, or other database libraries
  - Circe, Play JSON, or other JSON libraries
  - Cats, Cats Effect, or other functional programming libraries
- **Go Ecosystem**:
  - Gin, Echo, or other web frameworks
  - GORM, sqlx for database access
  - Gorilla toolkit components
  - Prometheus client libraries
- **Authentication/Authorization**: OAuth, JWT, SAML implementations
- **Monitoring & Observability**: Logging, metrics, tracing libraries
- **Testing Frameworks**: ScalaTest, Go testing package, testcontainers

## Investigation Checklist

Examine these files and directories:
- [ ] `build.sbt`, `project/`, `go.mod`, `go.sum`
- [ ] `application.conf`, `reference.conf` (Akka configuration)
- [ ] `Dockerfile`, `docker-compose.yml`, `.dockerignore`
- [ ] Kubernetes manifests (`k8s/`, `deploy/`, `manifests/`)
- [ ] Helm charts (`charts/`, `helm/`)
- [ ] `kustomization.yaml`, Kustomize overlays
- [ ] EKS-specific configurations (IAM roles, service accounts)
- [ ] Configuration files (`.env`, `config/`, ConfigMaps, Secrets)
- [ ] Database migration files and schema definitions
- [ ] API documentation (OpenAPI/Swagger specs)
- [ ] Infrastructure as Code (Terraform, CloudFormation, CDK)
- [ ] CI/CD pipeline configurations (GitHub Actions, GitLab CI, Jenkins)
- [ ] Monitoring and logging configurations (Prometheus, Grafana, ELK)
- [ ] Akka actor system configurations and cluster settings
- [ ] Go service main files and initialization patterns
- [ ] Health check endpoints and readiness/liveness probes

## Docker & Kubernetes Analysis

### Container Architecture
- **Multi-stage Builds**: Analyze build optimization and layer caching
- **Base Images**: Identify base images (Alpine, distroless, scratch)
- **Security Scanning**: Vulnerability scanning and image hardening
- **Image Tagging**: Versioning and deployment strategies
- **Resource Optimization**: Image size, startup time, memory usage

### Kubernetes Deployment Patterns
- **Deployment Strategies**: Rolling updates, blue-green, canary deployments
- **Resource Management**: CPU/memory requests and limits
- **Pod Disruption Budgets**: Availability and resilience configurations
- **Horizontal Pod Autoscaler**: Scaling based on metrics
- **Vertical Pod Autoscaler**: Resource optimization
- **Service Mesh**: Traffic management and security policies
- **Ingress Controllers**: External traffic routing and SSL termination
- **Network Policies**: Pod-to-pod communication restrictions

### EKS Integration
- **IAM Roles for Service Accounts**: AWS service integration
- **AWS Load Balancer Controller**: ALB/NLB integration
- **EBS CSI Driver**: Persistent volume management
- **AWS Secrets Manager**: Secret management integration
- **CloudWatch Integration**: Logging and monitoring
- **VPC Configuration**: Networking and security groups

## Technology-Specific Analysis

### Scala/Akka Actor System Architecture
- **Actor Hierarchies**: Map parent-child relationships and supervision strategies
- **Message Protocols**: Document message types and actor communication patterns
- **Akka Cluster**: Identify cluster roles, sharding strategies, and distributed data
- **Akka Persistence**: Event sourcing patterns, snapshot strategies
- **Akka Streams**: Graph DSL usage, materialization strategies
- **Kubernetes Integration**: Akka Cluster bootstrap, discovery mechanisms

### Go Service Patterns
- **Goroutine Management**: Identify worker pools, pipeline patterns
- **Channel Usage**: Buffered vs unbuffered channels, select statements
- **Context Propagation**: Request context handling and cancellation
- **Error Handling**: Error wrapping patterns and sentinel errors
- **Dependency Injection**: Service initialization and dependency management
- **Graceful Shutdown**: Signal handling and cleanup patterns

## Output Requirements

Based on analysis, create two comprehensive files:

### ai-docs/ARCHITECTURE.md
- System overview and architectural decisions
- **Mermaid Architecture Diagram**: Create a comprehensive diagram showing:
  - System components and their relationships
  - Data flow between services
  - External dependencies and integrations
  - Kubernetes deployment topology
  - Actor system hierarchies (for Akka services)
  - Database connections and message queue flows
- Akka actor system design and Go service architecture
- Container and Kubernetes architecture
- Component interaction descriptions
- Data flow descriptions including actor message flows
- Scalability and performance considerations
- Security architecture (RBAC, network policies, service mesh)
- Deployment strategies and CI/CD pipelines
- Disaster recovery and backup strategies

### ai-docs/README.md (Technology Stack Section)
- Complete technology inventory with Scala/Go focus
- Akka module usage (HTTP, Streams, Persistence, Cluster)
- Go framework and library choices
- Docker and Kubernetes configurations
- EKS-specific integrations and AWS services
- Version information where available
- Integration patterns between technologies
- Rationale for technology choices (if evident)
- Potential technical debt or upgrade paths
- Dependencies and their purposes
- Monitoring and observability stack

## Standard ai-docs File Templates

Initialize the following template files in `ai-docs/` directory:

### README.md
**IMPORTANT**: Must reflect ACTUAL current implementation state.

```markdown
# [Actual Repository Name from codebase]

## Overview
[Actual description based on what the repository currently does - analyze code to understand real functionality]

## Key Features - IMPLEMENTED
- [Actually implemented feature 1 - verify in codebase]
- [Actually implemented feature 2 - verify in codebase] 
- [Actually implemented feature 3 - verify in codebase]

## Key Features - IN PROGRESS
- [Feature currently being developed]
- [Feature with partial implementation]

## Quick Start
[Current working setup and usage instructions - test these work]

## Technology Stack - CURRENT
[Actual dependencies from package.json, go.mod, build files - scan codebase for real stack]

## Architecture
See [ARCHITECTURE.md](ARCHITECTURE.md) for current system design and implemented components.

## API
See [API.md](API.md) for currently available external endpoints and working examples.

## Development
```

**Creation Requirements**:
- Scan `package.json`, `go.mod`, `requirements.txt`, etc. for actual dependencies
- Test described setup processes to ensure they work
- Verify all listed features are actually implemented in the codebase

### API.md
**IMPORTANT**: Document only EXTERNAL APIs and interfaces. Do NOT include internal domain APIs.

```markdown
# External API Documentation - Current Implementation

## Overview
[Description of external APIs and interfaces the system provides or consumes]

## External APIs Provided - CURRENTLY AVAILABLE

### [External API Group]
#### [External API Endpoint Name]
- **Method:** [HTTP method for external consumers]
- **Path:** [Public API path]
- **Description:** [What this external endpoint provides]
- **Request:** [External request format]
- **Response:** [External response format]
- **Authentication:** [External authentication method]
- **Example:** [Working example for external consumers]
- **Status:** [✅ Working | ⚠️ Partially Implemented | ❌ Not Working]

## External APIs Consumed - CURRENTLY INTEGRATED

### [Third-party Service Name]
#### [External Service Endpoint]
- **Service:** [Name of external service]
- **Purpose:** [Why the system integrates with this API]
- **Authentication:** [How the system authenticates with external service]
- **Data Format:** [Request/response format used]
- **Example:** [Integration example]
- **Status:** [✅ Working | ⚠️ Partially Implemented | ❌ Not Working]

## External Interfaces - NOT YET IMPLEMENTED
### [Planned External Integration]
- [List external APIs that are planned but not yet integrated]
```

**Documentation Requirements**:
- Scan external API route handlers and controllers
- Document third-party service integrations
- Test external endpoints and integrations
- Focus ONLY on external-facing APIs and consumed external services
- Do NOT document internal domain APIs or business logic endpoints

### SCHEMA.md
**IMPORTANT**: Document only EXTERNAL database schemas and repository entities. Do NOT include internal domain entities.

```markdown
# External Data Schema - Current Implementation

## Overview
[Description of external database schemas and repository entity definitions that the system interfaces with]

## External Database Schema - EXISTING TABLES
[External database tables, relationships, and constraints that the system connects to - scan integration code and external API documentation]

```sql
-- External table definitions that the system interfaces with
[Include CREATE TABLE statements for external databases the system connects to]
```

## Repository Entities - IMPLEMENTED
[Data structures that represent external repository entities - from actual repository interface code]

```[language]
// Repository entity definitions from code
[Include real struct/class/interface definitions for external data entities]
```

## External API Data Models
[Data models for external APIs and services the system integrates with]

## Database Migrations - APPLIED
- [List of applied migrations for external database integrations]
- [Current migration status and version for external schemas]

## External Entities - PLANNED BUT NOT IMPLEMENTED
[Planned external data structures not yet integrated]
```

**Documentation Requirements**:
- Scan external database connection and integration code
- Extract repository entity definitions from code (structs, classes, interfaces)
- Document external API data models and schemas
- Focus ONLY on external data entities, NOT internal domain models

### USAGE.md
```markdown
# Usage Guide

## Overview
[How to use this system]

## Command Line Interface
[CLI commands and options]

## Web Interface
[UI usage instructions]

## Configuration
[Configuration options and settings]

## Examples
[Common usage examples]
```

### DEVELOPMENT.md
```markdown
# Development Guide

## Coding Standards
[Code style guidelines and conventions]

## Technology Stack
[Development tools, frameworks, libraries]

## Code Structure
[Project organization and file structure]

## Testing
See [TESTING.md](TESTING.md) for testing guidelines.

## Building
[Build commands and processes]
```

### TESTING.md
```markdown
# Testing

## Test Strategy
[Testing approach and philosophy]

## Running Tests
\`\`\`bash
# Run all tests
[test command]

# Run specific test suite
[specific test command]
\`\`\`

## Test Coverage
[Coverage requirements and how to check]

## Writing Tests
[Guidelines for writing new tests]

## Test Data
[Test data setup and management]
```

## Additional Template Files

Create empty template files for optional documentation:
- `INTEGRATIONS.md`

## Mermaid Diagram Guidelines

When creating the Mermaid architecture diagram, include:

1. **System Overview**: Use `graph TD` or `graph LR` for overall system architecture
2. **Service Relationships**: Show microservices and their dependencies
3. **Data Flow**: Indicate direction of data movement with arrows
4. **External Systems**: Include databases, message queues, external APIs
5. **Kubernetes Components**: Show pods, services, ingresses where relevant
6. **Actor Hierarchies**: For Akka systems, show actor supervision trees
7. **Network Boundaries**: Indicate security boundaries and network policies

Example structure:
```mermaid
classDef appLayer fill:#d4edda,stroke:#155724,stroke-width:2px,color:#000
classDef apiLayer fill:#d1ecf1,stroke:#0c5460,stroke-width:2px,color:#000
classDef infraLayer fill:#fff3cd,stroke:#856404,stroke-width:2px,color:#000
classDef external fill:#f8d7da,stroke:#721c24,stroke-width:2px,color:#000

graph TD
    A[Client]:::external --> B[Load Balancer]:::infraLayer
    B --> C[API Gateway]:::apiLayer
    C --> D[Service A - Scala/Akka]:::appLayer
    C --> E[Service B - Go]:::appLayer
    D --> F[Database]:::external
    E --> G[Message Queue]:::external
    D --> H[Actor System]:::appLayer
    E --> I[Worker Pool]:::appLayer
    
    subgraph "Kubernetes Cluster"
        C
        D
        E
        F
        G
    end
```

## Final Instructions

1. **Execute Both Phases**: Run project initialization first, then repository analysis
2. **Do NOT overwrite existing files** - check if files exist before creating
3. **Create directory structure** - ensure `ai-docs/` and `tasks/` directories exist
4. **Apply content guidelines** - ensure all documentation follows conciseness requirements
5. **Provide comprehensive summary** - list all files created, analysis findings, and next steps
6. **Git repository check** - ensure we're in a git repository before initializing
7. **Update workflow documentation** - Reference this unified project setup process in workflow documentation