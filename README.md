# Benefit Verification App

The **Benefit Verification App** is a Salesforce Health Cloud application designed to streamline benefit verification processes. It enables users to create `CareBenefitVerifyRequest` records, send verification requests to an external API, and create associated Case records (in bulk operations) assigned to the `Care_Rep_Queue` for Care Representatives to process. The application includes a REST API endpoint to handle verification results and create `CoverageBenefit` records. It uses Named Credentials for secure API callouts, supports bulk operations, and includes robust error handling and logging using a custom `Logger__c` object.

## Overview

This app allows healthcare organizations to:
- Create benefit verification requests directly in Salesforce.
- Send requests to an external API and receive responses seamlessly.
- Automatically create Cases assigned to the Care Representatives queue.
- Maintain secure and reliable integrations with external systems using Named Credentials.
- Perform bulk operations to handle multiple requests efficiently.
- Capture errors and logs with the custom `Logger__c` object for auditing and debugging.

## Key Features

**Create Benefit Verification Requests**  
Users can submit single or bulk requests via Apex or a Lightning Web Component (LWC).

**Case Management**  
Bulk requests create a Case record assigned to the `Care_Rep_Queue` for the first request in the batch.

**External API Integration**  
Sends verification requests to an external API using the `Benefit_Verification_API` Named Credential.

**REST API Endpoint**  
Processes verification results at `/care-benefit-verification-result`, creating `CoverageBenefit` records.

**Error Handling**  
Validates inputs (ICD-10, CPT codes), retries transient API errors (up to 3 attempts), and logs errors to `Logger__c`.

**Bulkification**  
Supports bulk creation of `CareBenefitVerifyRequest` records and associated `Case` records.

**Testing**  
Comprehensive unit tests for `BenefitVerificationController` and `BenefitVerificationResultAPI`.

## Repository Structure

force-app/main/default/
├── classes/
│   ├── BenefitVerificationController.cls
│   ├── BenefitVerificationControllerTest.cls
│   ├── BenefitVerificationResultAPI.cls
│   ├── BenefitVerificationResultAPITest.cls
├── objects/
│   ├── Account
│    ├── CareBenefitVerifyRequest__c
│    ├── CoverageBenefit
│    ├── Case
|    ├── Logger
├── namedCredentials/
│   ├── Benefit_Verification_API
├── queues/
│   ├── Care_Rep_Queue.queue-meta.xml


## Installation & Setup

1. **Deploy Metadata**  
   Deploy all metadata in this repository (Apex classes, objects, fields, queues, named credentials, and LWCs) to your Salesforce org using Salesforce CLI, Workbench, or your preferred deployment tool.

2. **Configure Named Credential**  
   Update the `Benefit_Verification_API` named credential with the external API endpoint and authentication details specific to your integration.

3. **Assign Permission Set**  
   Assign the `BenefitVerificationAccess` permission set to users who need to create or manage benefit verification requests.

4. **Verify Queue**  
   Make sure the `Care_Rep_Queue` exists in your org for Case assignment.

5. **Test Setup**  
   Run the included test classes `BenefitVerificationControllerTest` and `BenefitVerificationResultAPITest` to ensure successful configuration.

## REST API Endpoint

- **URL:** `/services/apexrest/care-benefit-verification-result`
- **Method:** `POST`
- **Description:** Receives verification results from the external API, processes them, and creates `CoverageBenefit` records linked to `CareBenefitVerifyRequest`.

### Sample Request

```json
{
  "requestId": "a01xx0000001XYZ",
  "status": "Approved",
  "statusReason": "Coverage verified successfully"
}
## Sample Successful Response


{
  "success": true,
  "message": "CoverageBenefit created and linked to CareBenefitVerifyRequest a01xx0000001XYZ."
}
## Sample Error Response

{
  "success": false,
  "error": "Invalid request: Missing required field 'requestId'."
}
##  Error Handling
Requests are validated to ensure required fields like requestId, status, and statusReason are present.

Transient API errors trigger up to 3 retry attempts with exponential backoff.

Errors and exceptions are logged in Logger__c with detailed messages and stack traces.