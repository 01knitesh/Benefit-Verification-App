@IsTest
private class BenefitVerificationControllerTest {
    @TestSetup
    static void setup() {
        // Create queue
        Group queue = new Group(Name = 'Care_Rep_Queue', Type = 'Queue');
        insert queue;
        QueueSobject queueSobject1 = new QueueSobject(QueueId = queue.Id, SobjectType = 'CareBenefitVerifyRequest');
        QueueSobject queueSobject2 = new QueueSobject(QueueId = queue.Id, SobjectType = 'Case');
        insert new List<QueueSobject>{queueSobject1, queueSobject2};

        // Create test data
        Account patient = new Account(
            FirstName = 'John',
            LastName = 'Doe',
            PersonBirthdate = Date.newInstance(1990, 1, 1),
            Gender__c = 'Male',
            NPI__c = '1234567890'
        );
        insert patient;

        MemberPlan memberPlan = new MemberPlan(
            Name = 'Aetna Plan',
            Insurance_Provider_Name__c = 'Aetna',
            Policy_Number__c = '123456',
            Group_Number__c = 'GRP123',
            SubscriberID = 'SUB123',
            MemberId = patient.Id
        );
        insert memberPlan;

        Account provider = new Account(
            FirstName = 'Jane',
            LastName = 'Smith',
            NPI__c = '9876543210'        );
        insert provider;
    }

    @IsTest
    static void testCreateBenefitVerificationRequestSuccess() {
        Test.setMock(HttpCalloutMock.class, new MockBenefitVerificationResponse());

        Account patient = [SELECT Id FROM Account WHERE FirstName = 'John' LIMIT 1];
        MemberPlan memberPlan = [SELECT Id FROM MemberPlan WHERE Insurance_Provider_Name__c = 'Aetna' LIMIT 1];
        Account provider = [SELECT Id FROM Account WHERE FirstName = 'Jane' LIMIT 1];

        BenefitVerificationController.BenefitRequestWrapper request = new BenefitVerificationController.BenefitRequestWrapper();
        request.patientId = patient.Id;
        request.memberPlanId = memberPlan.Id;
        request.providerId = provider.Id;
        request.service = new BenefitVerificationController.ServiceWrapper();
        request.service.serviceType = 'Consultation';
        request.service.serviceDate = Date.today();
        request.service.diagnosisCode = 'J45.9';
        request.service.procedureCode = '99213';

        Test.startTest();
        String requestId = BenefitVerificationController.createBenefitVerificationRequest(request);
        Test.stopTest();

        // Verify CareBenefitVerifyRequest
        CareBenefitVerifyRequest cbvr = [
            SELECT Id, Status, PayerId, MemberPlanId, ProviderId, ServiceType__c, 
                   ServiceDate__c, DiagnosisCode__c, ProcedureCode__c, CaseId
            FROM CareBenefitVerifyRequest 
            WHERE Id = :requestId
        ];
        System.assertNotEquals(null, requestId, 'Request ID should not be null');
        System.assertEquals('Acknowledged', cbvr.Status, 'Status should be Acknowledged');
        System.assertEquals(patient.Id, cbvr.PayerId, 'PayerId should match');
        System.assertEquals(memberPlan.Id, cbvr.MemberPlanId, 'MemberPlanId should match');
        System.assertEquals(provider.Id, cbvr.ProviderId, 'ProviderId should match');
        System.assertEquals('Consultation', cbvr.ServiceType__c, 'Service type should match');
        System.assertEquals(Date.today(), cbvr.ServiceDate__c, 'Service date should match');
        System.assertEquals('J45.9', cbvr.DiagnosisCode__c, 'Diagnosis code should match');
        System.assertEquals('99213', cbvr.ProcedureCode__c, 'Procedure code should match');
        System.assertEquals(null, cbvr.CaseId, 'CaseId should be null for single request');
    }

    @IsTest
    static void testCreateBenefitVerificationRequestInvalidInput() {
        BenefitVerificationController.BenefitRequestWrapper request = new BenefitVerificationController.BenefitRequestWrapper();
        request.patientId = null;
        request.memberPlanId = null;
        request.providerId = null;
        request.service = new BenefitVerificationController.ServiceWrapper();
        request.service.serviceType = '';
        request.service.diagnosisCode = 'INVALID';
        request.service.procedureCode = '123';

        Test.startTest();
        try {
            BenefitVerificationController.createBenefitVerificationRequest(request);
            System.assert(false, 'Expected an exception for missing required fields');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Missing required fields'), 'Expected missing fields error');
        }

        // Test invalid ICD-10 code
        request.patientId = [SELECT Id FROM Account LIMIT 1].Id;
        request.memberPlanId = [SELECT Id FROM MemberPlan LIMIT 1].Id;
        request.providerId = [SELECT Id FROM Account WHERE FirstName = 'Jane' LIMIT 1].Id;
        request.service.serviceType = 'Consultation';
        try {
            BenefitVerificationController.createBenefitVerificationRequest(request);
            System.assert(false, 'Expected an exception for invalid ICD-10 code');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Invalid ICD-10 code format'), 'Expected ICD-10 error');
        }

        // Test invalid CPT code
        request.service.diagnosisCode = 'J45.9';
        try {
            BenefitVerificationController.createBenefitVerificationRequest(request);
            System.assert(false, 'Expected an exception for invalid CPT code');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Invalid CPT code format'), 'Expected CPT error');
        }
        Test.stopTest();

        // Verify error logs
        List<Logger__c> logs = [SELECT Name, Error_Message__c FROM Logger__c];
        System.assertEquals(3, logs.size(), 'Three error logs should be created');
    }

    @IsTest
    static void testCreateBenefitVerificationRequestInvalidIds() {
        BenefitVerificationController.BenefitRequestWrapper request = new BenefitVerificationController.BenefitRequestWrapper();
        request.patientId = '001000000000000AAA';
        request.memberPlanId = 'a0M000000000000AAA';
        request.providerId = '001000000000000AAA';
        request.service = new BenefitVerificationController.ServiceWrapper();
        request.service.serviceType = 'Consultation';
        request.service.diagnosisCode = 'J45.9';
        request.service.procedureCode = '99213';

        Test.startTest();
        try {
            BenefitVerificationController.createBenefitVerificationRequest(request);
            System.assert(false, 'Expected an exception for invalid IDs');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Invalid record ID'), 'Expected invalid ID error');
        }
        Test.stopTest();

        // Verify error log
        List<Logger__c> logs = [SELECT Name, Error_Message__c FROM Logger__c];
        System.assertEquals(1, logs.size(), 'One error log should be created');
        System.assertEquals('Error creating benefit verification request', logs[0].Name, 'Log context should match');
    }

    @IsTest
    static void testCreateBulkBenefitVerificationRequestsSuccess() {
        Test.setMock(HttpCalloutMock.class, new MockBenefitVerificationResponse());

        Account patient = [SELECT Id FROM Account WHERE FirstName = 'John' LIMIT 1];
        MemberPlan memberPlan = [SELECT Id FROM MemberPlan WHERE Insurance_Provider_Name__c = 'Aetna' LIMIT 1];
        Account provider = [SELECT Id FROM Account WHERE FirstName = 'Jane' LIMIT 1];

        BenefitVerificationController.BenefitRequestWrapper request = new BenefitVerificationController.BenefitRequestWrapper();
        request.patientId = patient.Id;
        request.memberPlanId = memberPlan.Id;
        request.providerId = provider.Id;
        request.service = new BenefitVerificationController.ServiceWrapper();
        request.service.serviceType = 'Consultation';
        request.service.serviceDate = Date.today();
        request.service.diagnosisCode = 'J45.9';
        request.service.procedureCode = '99213';
        List<BenefitVerificationController.BenefitRequestWrapper> requests = new List<BenefitVerificationController.BenefitRequestWrapper>{request};

        Test.startTest();
        List<String> requestIds = BenefitVerificationController.createBulkBenefitVerificationRequests(requests);
        Test.stopTest();

        // Verify CareBenefitVerifyRequest
        System.assertEquals(1, requestIds.size(), 'One request should be created');
        CareBenefitVerifyRequest cbvr = [
            SELECT Id, Status, CaseId, PayerId, MemberPlanId, ProviderId
            FROM CareBenefitVerifyRequest 
            WHERE Id = :requestIds[0]
        ];
        System.assertEquals('Acknowledged', cbvr.Status, 'Status should be Acknowledged');
        System.assertNotEquals(null, cbvr.CaseId, 'CaseId should be set');
        System.assertEquals(patient.Id, cbvr.PayerId, 'PayerId should match');
        System.assertEquals(memberPlan.Id, cbvr.MemberPlanId, 'MemberPlanId should match');
        System.assertEquals(provider.Id, cbvr.ProviderId, 'ProviderId should match');

        // Verify Case
        Case caseRecord = [
            SELECT OwnerId, Subject, Status, Priority, AccountId
            FROM Case where id = :cbvr.CaseId
        ];
        System.assertEquals([SELECT Id FROM Group WHERE Name = 'Care_Rep_Queue'].Id, caseRecord.OwnerId, 'Case should be assigned to queue');
        System.assertEquals('Benefit Verification', caseRecord.Subject, 'Case subject should match');
        System.assertEquals('New', caseRecord.Status, 'Case status should be New');
        System.assertEquals('Medium', caseRecord.Priority, 'Case priority should be Medium');
        System.assertEquals(patient.Id, caseRecord.AccountId, 'Case should be linked to patient');
    }

    @IsTest
    static void testCreateBulkBenefitVerificationRequestsInvalidInput() {
        BenefitVerificationController.BenefitRequestWrapper request = new BenefitVerificationController.BenefitRequestWrapper();
        request.patientId = null;
        request.memberPlanId = null;
        request.providerId = null;
        request.service = new BenefitVerificationController.ServiceWrapper();
        request.service.serviceType = '';
        request.service.diagnosisCode = 'INVALID';
        request.service.procedureCode = '123';
        List<BenefitVerificationController.BenefitRequestWrapper> requests = new List<BenefitVerificationController.BenefitRequestWrapper>{request};

        Test.startTest();
        try {
            BenefitVerificationController.createBulkBenefitVerificationRequests(requests);
            System.assert(false, 'Expected an exception for invalid input');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Missing required fields'), 'Expected missing fields error');
        }
        Test.stopTest();

        // Verify no records created
        List<CareBenefitVerifyRequest> cbvrs = [SELECT Id FROM CareBenefitVerifyRequest];
        System.assertEquals(0, cbvrs.size(), 'No requests should be created');
        List<Case> cases = [SELECT Id FROM Case];
        System.assertEquals(0, cases.size(), 'No cases should be created');
    }

    @IsTest
    static void testSendToExternalAPIError() {
        Test.setMock(HttpCalloutMock.class, new MockBenefitVerificationErrorResponse());

        Account patient = [SELECT Id FROM Account WHERE FirstName = 'John' LIMIT 1];
        MemberPlan memberPlan = [SELECT Id FROM MemberPlan WHERE Insurance_Provider_Name__c = 'Aetna' LIMIT 1];
        Account provider = [SELECT Id FROM Account WHERE FirstName = 'Jane' LIMIT 1];

        CareBenefitVerifyRequest cbvr = new CareBenefitVerifyRequest(
            PayerId = patient.Id,
            MemberPlanId = memberPlan.Id,
            ProviderId = provider.Id,
            ServiceType__c = 'Consultation',
            ServiceDate__c = Date.today(),
            DiagnosisCode__c = 'J45.9',
            ProcedureCode__c = '99213',
            Status = 'Pending'
        );
        insert cbvr;

        Test.startTest();
        BenefitVerificationController.sendToExternalAPI(cbvr.Id);
        Test.stopTest();

        // Verify error state
        cbvr = [SELECT Status, StatusReason FROM CareBenefitVerifyRequest WHERE Id = :cbvr.Id];
        System.assertEquals('Error', cbvr.Status, 'Status should be Error');
        System.assert(cbvr.StatusReason.contains('Max retries reached'), 'StatusReason should indicate max retries');

        // Verify error log
        List<Logger__c> logs = [SELECT Name, Error_Message__c FROM Logger__c];
        System.assertEquals(1, logs.size(), 'One error log should be created');
        System.assertEquals('Error calling external API', logs[0].Name, 'Log context should match');
        System.assert(logs[0].Error_Message__c.contains('Max retries reached'), 'Log error message should match');
    }


public class MockBenefitVerificationResponse implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        res.setBody('{"status": "Acknowledged", "statusReason": "Request received"}');
        res.setStatusCode(200);
        return res;
    }
}

public class MockBenefitVerificationErrorResponse implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        res.setBody('{"error": "Server error"}');
        res.setStatusCode(500);
        return res;
    }

}
}