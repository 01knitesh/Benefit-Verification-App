@RestResource(urlMapping='/care-benefit-verification-result')
global with sharing class BenefitVerificationResultAPI {
    @HttpPost
    global static void processVerificationResult() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        try {
            // Validate request
            if (req.requestBody == null) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, String>{'error' => 'Empty request body'}));
                return;
            }
			String requestBodyString = req.requestBody == null ? null : req.requestBody.toString();
        System.debug('Request body string: ' + requestBodyString);
        
        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(requestBodyString);

            String requestId = (String) payload.get('requestId');
            String status = (String) payload.get('status');
            String statusReason = (String) payload.get('statusReason');

            // Validate required fields
            if (String.isBlank(requestId) || String.isBlank(status)) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, String>{'error' => 'Missing required fields'}));
                return;
            }

            // Verify CareBenefitVerifyRequest exists
            List<CareBenefitVerifyRequest> requests = [SELECT Id, Name, MemberPlanId, MemberPlan.Name FROM CareBenefitVerifyRequest WHERE Id = :requestId LIMIT 1];
            if (requests.isEmpty()) {
                res.statusCode = 404;
                res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, String>{'error' => 'Invalid request ID'}));
                return;
            }

            // Create CoverageBenefit record
            CoverageBenefit benefit = new CoverageBenefit();
            benefit.Name = 'Coverage Benefit for '+requests[0].MemberPlan.Name;
            benefit.MemberPlanId = requests[0].MemberPlanId;
            benefit.CareBenefitVerifyRequestId = requestId;
            
            insert benefit;
			System.debug('benefit'+benefit);
            res.statusCode = 201;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, String>{'message' => 'CoverageBenefit created', 'benefitId' => benefit.Id}));
        } catch (Exception e) {
            BenefitVerificationController.logError('Error processing verification result', e);
            res.statusCode = 500;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, String>{'error' => e.getMessage()}));
        }
    }
}