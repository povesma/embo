# Generating a Product Requirements Document (PRD)

**🔑 KISS Principle: Keep It Stupid Simple**
All solutions must follow the KISS principle - favor simplicity over complexity.

Create a focused Product Requirements Document (PRD) in Markdown format that captures business requirements, user needs, and success criteria. The PRD should be clear, actionable, and suitable for product managers and developers to understand the feature's business value and user-focused functionality.

## Process
1. **Receive Initial Prompt:** The user provides a brief description or request
   for a new feature or functionality.
2. **Request Jira Task ID:** If not provided, ask the user for the Jira task ID
   (e.g., "Please provide the Jira task ID for this feature (e.g., ABC-123)").
3. **Ask Clarifying Questions:** Before writing the PRD, the AI *must* ask
   clarifying questions to gather sufficient detail. The goal is to understand
   the "what" and "why" of the feature, not necessarily the "how" (which the
   developer will figure out).
4. **Generate PRD:** Based on the initial prompt and the user's answers to the
   clarifying questions, generate a PRD using the structure outlined below.
5. **Create Feature Folder & Save PRD:** Create a folder named `[JIRA-ID]-[feature-name]` 
   inside the `/tasks` directory and save the generated document as 
   `[YYYY-MM-DD]-[JIRA-ID]-[feature-name]-prd.md` inside that folder, where 
   [YYYY-MM-DD] is the current date, which can be obtained by running `date +%Y-%m-%d`.

## Clarifying Questions (Examples)
The AI should adapt its questions based on the prompt, but here are some common areas to explore for product requirements:
- **Problem/Goal:** "What problem does this feature solve for the user?" or "What is the main business goal we want to achieve?"
- **Target Users:** "Who are the primary users of this feature? Can you describe different user personas?"
- **Success Metrics:** "How will we measure the success of this feature? What metrics matter most?"
- **User Personas:** "Can you describe the different types of users and their specific needs?"
- **Use Cases:** "What are the main use cases this feature should support?"
- **User Stories:** "Could you provide user stories in the format: As a [user type], I want to [perform action] so that [benefit/goal]?"
- **Acceptance Criteria:** "What are the key acceptance criteria that define 'done' for this feature?"
- **Feature Scope:** "What should this feature include? What should it explicitly NOT include?"
- **Business Rules:** "Are there any business rules or constraints that must be followed?"
- **Performance Requirements:** "Are there any performance, security, or usability requirements?"
- **Dependencies:** "Does this feature depend on other systems, features, or external services?"
- **Risks:** "What are the main risks or potential blockers for this feature?"
- **User Behavior:** "Can you describe step-by-step how users will interact with this feature?"

## PRD Structure
The generated PRD should include the following sections focused on product and business requirements:

1. **Introduction/Overview:** Briefly describe the feature and the business problem it solves. State the primary goal and value proposition.

2. **Objectives & Success Metrics:** List specific, measurable business objectives and how success will be measured (e.g., "Increase user engagement by 15%", "Reduce support tickets by 30%").

3. **User Personas & Use Cases:** 
   - Define target user personas with their characteristics and needs
   - Detail specific use cases each persona will accomplish
   - Include user stories in "As a [persona], I want to [action] so that [benefit]" format

4. **Feature Scope:**
   - **In Scope:** What features and functionality will be included
   - **Out of Scope:** What will explicitly NOT be included in this release
   - **Future Considerations:** Potential future enhancements

5. **Functional Requirements:** List specific functionalities with Cucumber/Gherkin scenarios:
   - Use clear, testable language
   - Include Given-When-Then scenarios for key behaviors
   - Number all requirements for easy reference

6. **Non-Functional Requirements:** Define quality attributes:
   - **Performance:** Response times, throughput requirements
   - **Security:** Authentication, authorization, data protection needs
   - **Usability:** User experience standards and accessibility requirements
   - **Reliability:** Uptime, error handling, recovery expectations
   - **Architecture:** System must adhere to **Clean Architecture** principles for maintainability and testability

7. **Dependencies & Risks:**
   - **Dependencies:** Other features, systems, or external services required
   - **Risks:** Potential blockers, technical challenges, or business risks
   - **Mitigation Strategies:** How to address identified risks

8. **Open Questions:** List any remaining questions or areas needing further clarification before development begins.

## Target Audience
The primary readers of the PRD include:
- **Product Managers**: Understanding business value and user needs
- **Developers**: Understanding what needs to be built and acceptance criteria  
- **QA Engineers**: Creating test scenarios from Cucumber specifications
- **Business Stakeholders**: Validating requirements meet business goals

Requirements should be explicit, unambiguous, and written in business language that technical and non-technical stakeholders can understand.

## PRD Output
- **Format:** Markdown (`.md`)
- **Location:** `/tasks/[JIRA-ID]-[feature-name]/`
- **Filename:** `[YYYY-MM-DD]-[JIRA-ID]-[feature-name]-prd.md`
- **Style:** Try and keep to 80 character row length. Trim empty characters in
  line ends. VERY IMPORTANT: Always end files with an empty line.
- **Header:** Start file with a Markdown header:
```markdown
# [feature-name] - Product Requirements Document

## Introduction/Overview
[Brief description of the feature and business problem it solves. State the primary goal and value proposition.]

## Objectives & Success Metrics
**Business Objectives:**
- [Objective 1 with measurable outcome]
- [Objective 2 with measurable outcome]

**Success Metrics:**
- [Metric 1]: [Target value and measurement method]
- [Metric 2]: [Target value and measurement method]

## User Personas & Use Cases

### User Personas
**[Persona 1 Name]**: [Role/Description]
- **Characteristics**: [Key traits and background]
- **Needs**: [Primary needs and pain points]
- **Goals**: [What they want to achieve]

**[Persona 2 Name]**: [Role/Description]
- **Characteristics**: [Key traits and background]  
- **Needs**: [Primary needs and pain points]
- **Goals**: [What they want to achieve]

### User Stories
- As a [persona], I want to [action] so that [benefit/goal]
- As a [persona], I want to [action] so that [benefit/goal]

### Use Cases
1. **[Use Case 1]**: [Description of scenario]
2. **[Use Case 2]**: [Description of scenario]

## Feature Scope

### In Scope
- [Feature/functionality 1]
- [Feature/functionality 2]

### Out of Scope
- [What will NOT be included in this release]
- [Explicitly excluded functionality]

### Future Considerations
- [Potential future enhancements]
- [Next iteration possibilities]

## Functional Requirements

### Cucumber/Gherkin Scenarios
```gherkin
Feature: [Feature name]

Scenario: [Scenario 1 name]
  Given [initial context]
  When [action performed]
  Then [expected outcome]
  And [additional verification]

Scenario: [Scenario 2 name]  
  Given [initial context]
  When [action performed]
  Then [expected outcome]
```

### Detailed Requirements
1. **[Requirement 1]**: The system must [specific functionality]
2. **[Requirement 2]**: The system must [specific functionality]

## Non-Functional Requirements

### Performance
- **Response Time**: [Maximum acceptable response time]
- **Throughput**: [Expected load/transactions per time unit]

### Security  
- **Authentication**: [Authentication requirements]
- **Authorization**: [Access control requirements]
- **Data Protection**: [Data privacy and security needs]

### Usability
- **User Experience**: [UX standards and guidelines]
- **Accessibility**: [Accessibility compliance requirements]

### Reliability
- **Uptime**: [Availability requirements]
- **Error Handling**: [Error recovery expectations]

### Architecture
- **Design Pattern**: System must follow **Clean Architecture** principles
- **Layer Separation**: Clear separation between domain, application, and infrastructure layers
- **Dependency Inversion**: Dependencies flow inward toward the domain core

## Dependencies & Risks

### Dependencies
- **Internal Dependencies**: [Other features/systems required]
- **External Dependencies**: [Third-party services/APIs required]

### Risks
- **Risk 1**: [Description] - *Mitigation*: [How to address]
- **Risk 2**: [Description] - *Mitigation*: [How to address]

## Open Questions
- [Question 1 requiring clarification]
- [Question 2 requiring clarification]
```

## Final instructions
1. Do NOT start implementing the PRD
2. Make sure to ask the user clarifying questions focused on product and business requirements
3. Take the user's answers to the clarifying questions and improve the PRD
4. Focus on business value, user needs, and acceptance criteria rather than technical implementation details
5. Include Cucumber/Gherkin scenarios for testable requirements
6. Consider suggesting the `/tech-design` command for technical architecture and implementation details
