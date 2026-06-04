public class PDFcoIntegration {
    
    public static final String API_KEY = 'tearnhardt21@gmail.com_79xrbakYcnQUpmnxvZBAFDMsziN7vP3Tf3LK71RXUDkxPXAmbpghUjewvqBgXzyz';
    private static final String API_URL = 'https://api.pdf.co/v1/pdf/edit/add';
    
    public static void addTextToPDF() {
        // Build request payload
        Map<String, Object> params = new Map<String, Object>();
        params.put('url', 'https://your-source-file-url.com/sample.pdf');
        params.put('name', 'output');
        params.put('type', 'annotation');
        params.put('x', 400);
        params.put('y', 600);
        params.put('text', 'APPROVED');
        params.put('fontname', 'Times New Roman');
        params.put('size', 24);
        params.put('color', 'FF0000');
        
        String jsonPayload = JSON.serialize(params);
        
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(API_URL);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('x-api-key', API_KEY);
            req.setBody(jsonPayload);
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            if (res.getStatusCode() == 200) {
                Map<String, Object> result = 
                    (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                System.debug('Output URL: ' + result.get('url'));
            } else {
                System.debug('Error: ' + res.getBody());
            }
        } catch (Exception e) {
            System.debug('Exception: ' + e.getMessage());
        }
    }
}