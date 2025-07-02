public with sharing class BenefitVerificationController {
    // Wrapper class for service details
    public class ServiceWrapper {
        @AuraEnabled public String serviceType { get; set; }
        @AuraEnabled public Date serviceDate { get; set; }
        @AuraEnabled public String diagnosisCode { get; set; }
        @AuraEnabled public String procedureCode { get; set; }
    }

    // Wrapper class for request input
    public class BenefitRequestWrapper {
        @AuraEnabled public Id patientId { get; set; }
        @AuraEnabled public Id memberPlanId { get; set; }
        @AuraEnabled public Id providerId { get; set; }
        @AuraEnabled public ServiceWrapper service { get; set; }
    }

    // Create a single request
    @AuraEnabled
    public static String createBenefitVerificationRequest(BenefitRequestWrapper request) {
        try {
            // Validate required fields
            if (request.patientId == null || request.memberPlanId == null || request.providerId == null || 
                request.service == null || String.isBlank(request.service.serviceType) ||
                String.isBlank(request.service.diagnosisCode) || String.isBlank(request.service.procedureCode)) {
                throw new CustomException('Missing required fields');
            }

            // Validate data formats
            if (!isValidICD10Code(request.service.diagnosisCode)) {
                throw new CustomException('Invalid ICD-10 code format');
            }
            if (!isValidCPTCode(request.service.procedureCode)) {
                throw new CustomException('Invalid CPT code format');
            }

            // Query Patient
            Account patient = [
                SELECT Id, FirstName, LastName, PersonBirthdate, Gender__c
                FROM Account
                WHERE Id = :request.patientId
                LIMIT 1
            ];

            // Query Insurance
            MemberPlan memberPlan = [
                SELECT Id, Insurance_Provider_Name__c, Policy_Number__c, Group_Number__c, SubscriberID
                FROM MemberPlan
                WHERE Id = :request.memberPlanId
                LIMIT 1
            ];

            // Query Provider
            Account provider = [
                SELECT Id, FirstName, LastName, NPI__c
                FROM Account
                WHERE Id = :request.providerId
                LIMIT 1
            ];

            // Create CareBenefitVerifyRequest record
            CareBenefitVerifyRequest cbvr = new CareBenefitVerifyRequest(
                PayerId = patient.Id,
                MemberPlanId = memberPlan.Id,
                ProviderId	 = provider.Id,
                ServiceType__c = request.service.serviceType,
                ServiceDate__c = request.service.serviceDate,
                DiagnosisCode__c = request.service.diagnosisCode,
                ProcedureCode__c = request.service.procedureCode,
                Status = 'Pending'
            );
            insert cbvr;

           

            // Send to external API
            sendToExternalAPI(cbvr.Id);

            return cbvr.Id;
        } catch (Exception e) {
            logError('Error creating benefit verification request', e);
            throw new AuraHandledException('Error: ' + e.getMessage());
        }
    }

    // Bulk request creation
    @AuraEnabled
    public static List<String> createBulkBenefitVerificationRequests(List<BenefitRequestWrapper> requests) {
        List<CareBenefitVerifyRequest> records = new List<CareBenefitVerifyRequest>();
        try {
            // Collect IDs for bulk queries
            Set<Id> patientIds = new Set<Id>();
            Set<Id> memberPlanIds = new Set<Id>();
            Set<Id> providerIds = new Set<Id>();
            for (BenefitRequestWrapper request : requests) {
                if (request.patientId == null || request.memberPlanId == null || request.providerId == null || 
                    request.service == null || String.isBlank(request.service.serviceType) ||
                    String.isBlank(request.service.diagnosisCode) || String.isBlank(request.service.procedureCode)) {
                    throw new CustomException('Missing required fields in request');
                }
                if (!isValidICD10Code(request.service.diagnosisCode)) {
                    throw new CustomException('Invalid ICD-10 code format');
                }
                if (!isValidCPTCode(request.service.procedureCode)) {
                    throw new CustomException('Invalid CPT code format');
                }
                patientIds.add(request.patientId);
                memberPlanIds.add(request.memberPlanId);
                providerIds.add(request.providerId);
            }

            // Bulk query Patient
            Map<Id, Account> patients = new Map<Id, Account>([
                SELECT Id, FirstName, LastName, PersonBirthdate, Gender__c
                FROM Account
                WHERE Id IN :patientIds
            ]);

            // Bulk query Insurance
            Map<Id, MemberPlan> memberPlans = new Map<Id, MemberPlan>([
                SELECT Id, Insurance_Provider_Name__c, Policy_Number__c, Group_Number__c, SubscriberID
                FROM MemberPlan
                WHERE Id IN :memberPlanIds
            ]);

            // Bulk query Provider
            Map<Id, Account> providers = new Map<Id, Account>([
                SELECT Id, FirstName, LastName, NPI__c
                FROM Account
                WHERE Id IN :providerIds
            ]);

            // Validate queried records
            for (BenefitRequestWrapper request : requests) {
                if (!patients.containsKey(request.patientId) || !memberPlans.containsKey(request.memberPlanId) || 
                    !providers.containsKey(request.providerId)) {
                    throw new CustomException('Invalid record ID provided');
                }

                CareBenefitVerifyRequest cbvr = new CareBenefitVerifyRequest(
                   PayerId = request.patientId,
                    MemberPlanId = request.memberPlanId,
                    ProviderId	 = request.providerId,
                    ServiceType__c = request.service.serviceType,
                    ServiceDate__c = request.service.serviceDate,
                    DiagnosisCode__c = request.service.diagnosisCode,
                    ProcedureCode__c = request.service.procedureCode,
                    Status= 'Pending'
                );
                records.add(cbvr);
            }
            insert records;

            // Assign to queue
            Group queue = [SELECT Id FROM Group WHERE Type = 'Queue' AND Name = 'Care_Rep_Queue' LIMIT 1];
            
            Case caseRecord = new Case(
                Subject = 'Benefit Verification',
                Status = 'New',
                Priority = 'Medium',
                AccountId =records[0].payerId,
                OwnerId = queue.Id
            );
            insert caseRecord;

            // Update CareBenefitVerifyRequest with Case reference
            records[0].CaseId = caseRecord.Id;
            update records[0];

            // Send to external API
            List<String> requestIds = new List<String>();
            for (CareBenefitVerifyRequest cbvr : records) {
                requestIds.add(cbvr.Id);
                sendToExternalAPI(cbvr.Id);
            }
            return requestIds;
        } catch (Exception e) {
            logError('Error creating bulk benefit verification requests', e);
            throw new AuraHandledException('Error: ' + e.getMessage());
        }
    }

    // Send request to external API with retry logic
    @Future(callout=true)
    public static void sendToExternalAPI(String requestId) {
        CareBenefitVerifyRequest cbvr = [
            SELECT Id, PayerId, MemberPlanId, ProviderId, ServiceType__c, ServiceDate__c, 
                   DiagnosisCode__c, ProcedureCode__c,
                   MemberPlan.Member.FirstName, MemberPlan.Member.LastName, MemberPlan.Member.PersonBirthdate, MemberPlan.Member.Gender__c,MemberPlan.Member.NPI__c,
                   MemberPlan.Insurance_Provider_Name__c, MemberPlan.Policy_Number__c, 
                   MemberPlan.Group_Number__c, MemberPlan.SubscriberID,
                   Provider.FirstName, Provider.LastName
            FROM CareBenefitVerifyRequest
            WHERE Id = :requestId 
            LIMIT 1
        ];

        

         HttpRequest httpReq = new HttpRequest();
        // Use Named Credential for endpoint and authentication
        httpReq.setEndpoint('callout:Benefit_Verification_API/benefit-verification-request');
        httpReq.setMethod('POST');
        httpReq.setHeader('Content-Type', 'application/json');
        httpReq.setTimeout(120000);


        // Construct JSON payload
        Map<String, Object> payload = new Map<String, Object>{
            'requestId' => cbvr.Id,
            'patient' => new Map<String, Object>{
                'firstName' => cbvr.MemberPlan.Member.FirstName,
                'lastName' => cbvr.MemberPlan.Member.LastName,
                'dateOfBirth' => cbvr.MemberPlan.Member.PersonBirthdate,
                'gender' => cbvr.MemberPlan.Member.Gender__c,
                    'NPI' => cbvr.MemberPlan.Member.NPI__c
            },
            'insurance' => new Map<String, Object>{
                'providerName' => cbvr.MemberPlan.Insurance_Provider_Name__c,
                'policyNumber' => cbvr.MemberPlan.Policy_Number__c,
                'groupNumber' => cbvr.MemberPlan.Group_Number__c,
                'subscriberId' => cbvr.MemberPlan.SubscriberID
            },
            'provider' => new Map<String, Object>{
                'npi' => '',
                'firstName' => cbvr.Provider.FirstName,
                'lastName' => cbvr.Provider.LastName
            },
            'service' => new Map<String, Object>{
                'type' => cbvr.ServiceType__c,
                'date' => cbvr.ServiceDate__c,
                'diagnosisCode' => cbvr.DiagnosisCode__c,
                'procedureCode' => cbvr.ProcedureCode__c
            }
        };
        httpReq.setBody(JSON.serialize(payload));

        Http http = new Http();
        Integer maxRetries = 3;
        Integer retryCount = 0;
        while (retryCount < maxRetries) {
            try {
                HttpResponse res = http.send(httpReq);
                if (res.getStatusCode() == 200) {
                    Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                    cbvr.Status = (String) response.get('status');
                    cbvr.StatusReason = (String) response.get('statusReason');
                    update cbvr;
                    return;
                } else if (res.getStatusCode() >= 500) {
                    retryCount++;
                    if (retryCount == maxRetries) {
                        throw new CustomException('Max retries reached: ' + res.getStatusCode());
                    }
                    continue;
                } else {
                    throw new CustomException('API Error: ' + res.getStatusCode() + ' - ' + res.getBody());
                }
            } catch (Exception e) {
                logError('Error calling external API', e);
                if (retryCount == maxRetries - 1) {
                    cbvr.Status = 'Error';
                    cbvr.StatusReason = e.getMessage();
                    update cbvr;
                    return;
                }
                retryCount++;
            }
        }
    }

    // Validation methods
    private static Boolean isValidICD10Code(String code) {
        // Basic ICD-10 validation (e.g., A00.0-Z99.9 format)
        return Pattern.matches('^[A-Z][0-9]{2}\\.[0-9]{1,4}$', code);
    }

    private static Boolean isValidCPTCode(String code) {
        // Basic CPT validation (5 digits)
        return Pattern.matches('^[0-9]{5}$', code);
    }

    // Error logging
    public static void logError(String context, Exception e) {
        Logger__c logEvent = new Logger__c(
            Name = context,
            Error_Message__c = e.getMessage(),
            Stack_Trace__c = e.getStackTraceString()
        );
        insert logEvent;
    }

    public class CustomException extends Exception {}
}