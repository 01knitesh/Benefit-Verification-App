# Benefit-Verification-App

Benefit Verification App
Overview
The Benefit Verification App is a Salesforce Health Cloud application designed to streamline benefit verification processes. It allows users to create CareBenefitVerifyRequest__c records, send verification requests to an external API, and create associated Case records assigned to a queue (Care_Rep_Queue) for Care Representatives to process. The application includes a REST API endpoint to handle verification results and create CoverageBenefit records. It uses Named Credentials for secure API callouts and includes robust error handling, bulkification, and logging.
Key Features

Create Benefit Verification Requests: Users can submit single or bulk requests via Apex or a Lightning Web Component (LWC).
Case Management: Each CareBenefitVerifyRequest__c creates a related Case assigned to the Care_Rep_Queue.
External API Integration: Sends verification requests to an external API using Named Credentials (Benefit_Verification_API).
REST API Endpoint: Processes verification results at /care-benefit-verification-result, creating CoverageBenefit records.
Error Handling: Validates inputs, retries transient API errors, and logs errors using Benefit_Verification_Log__e platform events.
Bulkification: Supports bulk creation of CareBenefitVerifyRequest__c and Case records.
Testing: Comprehensive unit tests for BenefitVerificationController and BenefitVerificationResultAPI.

Repository Structure
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

Prerequisites

Salesforce Org: A Salesforce org with Health Cloud installed.
Objects: CareBenefitVerifyRequest, CoverageBenefit, MemberPlan, Account, Case, and Logger.
Custom Field: Case (lookup to Case) on CareBenefitVerifyRequest.
Permissions: Users need access to the above objects and the Benefit_Verification_API Named Credential.
Tools: Salesforce CLI, VS Code with Salesforce Extensions, or another SFDX-compatible IDE.

Setup Instructions

Clone Repository:
git clone <repository-url>
cd BenefitVerificationApp


Authenticate with Salesforce Org:
sfdx force:auth:web:login -a <alias>


Deploy Source to Org:
sfdx force:source:push -u <alias>


Configure Named Credential:

Go to Setup > Named Credentials > New Named Credential.
Settings:
Label: Benefit_Verification_API
Name: Benefit_Verification_API
URL: https://infinitusmockbvendpoint-rji9z4.5sc6y6-2.usa-e2.cloudhub.io
Identity Type: Named Principal
Authentication Protocol: Password Authentication
Username: test_user
Password: test_password
Generate Authorization Header: Enabled


Save the Named Credential.


Set Up Queue:

In Setup > Queues, create or edit a queue named Care_Rep_Queue.
Add supported objects: CareBenefitVerifyRequest__c and Case.
Assign relevant users as queue members.


Configure Custom Field:

Ensure the Case__c lookup field on CareBenefitVerifyRequest__c is deployed (included in force-app/main/default/objects/CareBenefitVerifyRequest__c/fields/Case__c.field-meta.xml).
Verify Case has a lookup field CareBenefitVerifyRequest__c to CareBenefitVerifyRequest__c.


Assign Permissions:

Assign the BenefitVerificationAccess permission set to users:sfdx force:user:permset:assign -n BenefitVerificationAccess -u <alias>


Grant access to the Benefit_Verification_API Named Credential via Setup > Named Credential Access.


Add LWC to Page (Optional):

Add the benefitVerificationForm LWC to a Lightning App Page or Record Page using App Builder.



Testing
Unit Tests
Run unit tests to verify the functionality of BenefitVerificationController and BenefitVerificationResultAPI:
sfdx force:apex:test:run -u <alias> -c -r human -n BenefitVerificationControllerTest,BenefitVerificationResultAPITest

Manual Testing



Test REST Endpoint:

Use Postman or a similar tool to send a POST request:POST /services/apexrest/care-benefit-verification-result
Authorization: Bearer <session-token>
Content-Type: application/json

{
    "requestId": "<CareBenefitVerifyRequest__c_Id>",
    "status": "Verified",
    "statusReason": "Benefit verification completed"
}


Expected response:{
    "message": "CoverageBenefit created",
    "benefitId": "<CoverageBenefit_Id>"
}


Alternatively, test via Apex in Developer Console:RestRequest req = new RestRequest();
req.requestUri = '/services/apexrest/care-benefit-verification-result';
req.httpMethod = 'POST';
req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
    'requestId' => '<CareBenefitVerifyRequest__c_Id>',
    'status' => 'Verified',
    'statusReason' => 'Benefit verification completed'
}));
RestContext.request = req;
RestContext.response = new RestResponse();
BenefitVerificationResultAPI.processVerificationResult();
System.debug(RestContext.response.responseBody.toString());




Verify Records:

Query CareBenefitVerifyRequest__c:SELECT Id, Status__c, Case__c, Patient__c, Insurance__c, Provider__c
FROM CareBenefitVerifyRequest__c
WHERE Patient__r.FirstName = 'John'


Query CoverageBenefit:SELECT Id, Name, MemberPlanId, CareBenefitVerifyRequestId
FROM CoverageBenefit
WHERE CareBenefitVerifyRequestId != null


Query error logs:SELECT Context__c, Error_Message__c
FROM Benefit_Verification_Log__e





Sample Request Payload
For BenefitVerificationController:
{
    "patientId": "<Account_Id>",
    "memberPlanId": "<MemberPlan__c_Id>",
    "providerId": "<Account_Id>",
    "service": {
        "serviceType": "Consultation",
        "serviceDate": "2025-07-10",
        "diagnosisCode": "J45.9",
        "procedureCode": "99213"
    }
}

For BenefitVerificationResultAPI:
{
    "requestId": "<CareBenefitVerifyRequest__c_Id>",
    "status": "Verified",
    "statusReason": "Benefit verification completed"
}

Assumptions

The external API (https://infinitusmockbvendpoint-rji9z4.5sc6y6-2.usa-e2.cloudhub.io/benefit-verification-request) is available and responds with { "status": "Acknowledged", "statusReason": "Request received" } or similar.
Standard Health Cloud objects (CareBenefitVerifyRequest__c, CoverageBenefit, Case) and custom object MemberPlan__c are configured.
Lookup fields exist: Patient__c, Insurance__c, Provider__c, Case__c on CareBenefitVerifyRequest__c; CareBenefitVerifyRequest__c on Case; MemberPlanId, CareBenefitVerifyRequestId on CoverageBenefit.
ICD-10 and CPT code validation uses basic regex patterns (^[A-Z][0-9]{2}\\.[0-9]{1,4}$ for ICD-10, ^[0-9]{5}$ for CPT).

Challenges and Solutions

Challenge: Securing API credentials.
Solution: Used Named Credentials (Benefit_Verification_API) for secure storage and authentication.


Challenge: Handling transient API errors.
Solution: Implemented a retry mechanism (3 attempts) in BenefitVerificationController.


Challenge: Assigning tasks to Care Representatives.
Solution: Created Case records linked to CareBenefitVerifyRequest__c and assigned to Care_Rep_Queue.


Challenge: Validating REST inputs.
Solution: Added checks for empty body, missing fields, and invalid requestId in BenefitVerificationResultAPI.



Bonus Features

Case Integration: Each CareBenefitVerifyRequest__c creates a Case for queue-based task management.
Error Logging: Uses Benefit_Verification_Log__e platform events for robust error tracking.
Retry Logic: Handles transient API failures with up to 3 retries.
Bulkification: Supports bulk creation of CareBenefitVerifyRequest__c and Case records.
Comprehensive Testing: Unit tests cover success, error, and edge cases for both BenefitVerificationController and BenefitVerificationResultAPI.

Contributing

Fork the repository.
Create a feature branch (git checkout -b feature/<feature-name>).
Commit changes (git commit -m "Add <feature-name>").
Push to the branch (git push origin feature/<feature-name>).
Open a pull request.

License
This project is licensed under the MIT License. See the LICENSE file for details.
Contact
For questions or issues, contact the repository maintainer or open an issue in the
