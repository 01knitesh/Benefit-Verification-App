@IsTest
private class BenefitVerificationResultAPITest {
    @TestSetup
    static void setup() {
        // Create MemberPlan__c
        MemberPlan memberPlan = new MemberPlan(
            Name = 'Aetna Plan',
            Insurance_Provider_Name__c = 'Aetna',
            Policy_Number__c = '123456',
            Group_Number__c = 'GRP123',
            SubscriberID = 'SUB123'
        );
        insert memberPlan;

        // Create CareBenefitVerifyRequest__c
        CareBenefitVerifyRequest cbvr = new CareBenefitVerifyRequest(
            MemberPlanId = memberPlan.Id,
            Status = 'Pending',
            ServiceType__c = 'Consultation',
            ServiceDate__c = Date.today(),
            DiagnosisCode__c = 'J45.9',
            ProcedureCode__c = '99213'
        );
        insert cbvr;
    }

    @IsTest
    static void testProcessVerificationResultSuccess() {
        // Get test data
        CareBenefitVerifyRequest cbvr = [SELECT Id, MemberPlanId FROM CareBenefitVerifyRequest LIMIT 1];

        // Prepare REST request
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/care-benefit-verification-result';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'requestId' => cbvr.Id,
            'status' => 'Verified',
            'statusReason' => 'Benefit verification completed'
        }));
        RestContext.request = req;
        RestContext.response = new RestResponse();

        // Execute
        Test.startTest();
        BenefitVerificationResultAPI.processVerificationResult();
        Test.stopTest();

        // Verify response
        System.assertEquals(201, RestContext.response.statusCode, 'Status code should be 201');
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
        System.assertEquals('CoverageBenefit created', response.get('message'), 'Response message should match');
        System.assertNotEquals(null, response.get('benefitId'), 'Benefit ID should be returned');

        // Verify CoverageBenefit
        CoverageBenefit benefit = [
            SELECT Id, Name, MemberPlanId, CareBenefitVerifyRequestId
            FROM CoverageBenefit
            WHERE CareBenefitVerifyRequestId = :cbvr.Id
            LIMIT 1
        ];
        System.assertEquals('Coverage Benefit for Aetna Plan', benefit.Name, 'CoverageBenefit Name should match');
        System.assertEquals(cbvr.MemberPlanId, benefit.MemberPlanId, 'MemberPlanId should match');
        System.assertEquals(cbvr.Id, benefit.CareBenefitVerifyRequestId, 'CareBenefitVerifyRequestId should match');
    }

    @IsTest
    static void testProcessVerificationResultEmptyBody() {
        // Prepare REST request with empty body
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/care-benefit-verification-result';
        req.httpMethod = 'POST';
        req.requestBody = null;
        RestContext.request = req;
        RestContext.response = new RestResponse();

        // Execute
        Test.startTest();
        BenefitVerificationResultAPI.processVerificationResult();
        Test.stopTest();

        // Verify response
        System.assertEquals(400, RestContext.response.statusCode, 'Status code should be 400');
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
        System.assertEquals('Empty request body', response.get('error'), 'Error message should match');

        // Verify no CoverageBenefit created
        List<CoverageBenefit> benefits = [SELECT Id FROM CoverageBenefit];
        System.assertEquals(0, benefits.size(), 'No CoverageBenefit should be created');
    }

    @IsTest
    static void testProcessVerificationResultMissingFields() {
        // Prepare REST request with missing fields
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/care-benefit-verification-result';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'statusReason' => 'Missing fields test'
        }));
        RestContext.request = req;
        RestContext.response = new RestResponse();

        // Execute
        Test.startTest();
        BenefitVerificationResultAPI.processVerificationResult();
        Test.stopTest();

        // Verify response
        System.assertEquals(400, RestContext.response.statusCode, 'Status code should be 400');
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
        System.assertEquals('Missing required fields', response.get('error'), 'Error message should match');

        // Verify no CoverageBenefit created
        List<CoverageBenefit> benefits = [SELECT Id FROM CoverageBenefit];
        System.assertEquals(0, benefits.size(), 'No CoverageBenefit should be created');
    }

    @IsTest
    static void testProcessVerificationResultInvalidRequestId() {
        // Prepare REST request with invalid requestId
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/care-benefit-verification-result';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'requestId' => 'a0M000000000000AAA',
            'status' => 'Verified',
            'statusReason' => 'Invalid ID test'
        }));
        RestContext.request = req;
        RestContext.response = new RestResponse();

        // Execute
        Test.startTest();
        BenefitVerificationResultAPI.processVerificationResult();
        Test.stopTest();

        // Verify response
        System.assertEquals(404, RestContext.response.statusCode, 'Status code should be 404');
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
        System.assertEquals('Invalid request ID', response.get('error'), 'Error message should match');

        // Verify no CoverageBenefit created
        List<CoverageBenefit> benefits = [SELECT Id FROM CoverageBenefit];
        System.assertEquals(0, benefits.size(), 'No CoverageBenefit should be created');
    }

    @IsTest
    static void testProcessVerificationResultException() {
        // Mock an exception by querying a non-existent record (simulate DML failure)
        CareBenefitVerifyRequest cbvr = [SELECT Id, MemberPlanId FROM CareBenefitVerifyRequest LIMIT 1];
        delete cbvr; // Delete to force an exception

        // Prepare REST request
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/care-benefit-verification-result';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'requestId' => cbvr.Id,
            'status' => 'Verified',
            'statusReason' => 'Exception test'
        }));
        RestContext.request = req;
        RestContext.response = new RestResponse();

        // Execute
        Test.startTest();
        BenefitVerificationResultAPI.processVerificationResult();
        Test.stopTest();

        // Verify response
        System.assertEquals(500, RestContext.response.statusCode, 'Status code should be 500');
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
        System.assert(response.get('error').toString().contains('List has no rows'), 'Error message should indicate query failure');

        // Verify error log
        List<Logger__c> logs = [SELECT Name, Error_Message__c FROM Logger__c];
        System.assertEquals(1, logs.size(), 'Error log should be created');
        System.assertEquals('Error processing verification result', logs[0].Name, 'Log context should match');
        System.assert(logs[0].Error_Message__c.contains('List has no rows'), 'Log error message should match');

        // Verify no CoverageBenefit created
        List<CoverageBenefit> benefits = [SELECT Id FROM CoverageBenefit];
        System.assertEquals(0, benefits.size(), 'No CoverageBenefit should be created');
    }
}