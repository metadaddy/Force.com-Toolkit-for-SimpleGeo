/**
 * @author Pat Patterson - ppatterson@salesforce.com
 */

global with sharing class SimpleGeoController {
    static SimpleGeo client = new SimpleGeo();
    
    public SimpleGeoController() {}
    
    // Return JSON with latitude, longitude
    public static String getLocationFromIP() {
        String ip = ApexPages.CurrentPage().getHeaders().get('x-Salesforce-SIP');
        
        SimpleGeo.Context context = client.getContextFromIPAddress(ip);
        
        return '{latitude: "'+context.query.latitude+
            '",longitude:"'+context.query.longitude+'"}';
    }
    
    // Return simple address string
    @RemoteAction
    global static String getAddress(Double latitude, Double longitude) {
        Map<String, SimpleGeo.PropertyValue> properties = client.getContext(latitude, longitude).address.properties;
        String address = properties.containsKey('address') ? properties.get('address').getString() + ', ' : '';
        address += properties.containsKey('city') ? properties.get('city').getString() + ', ' : '';
        address += properties.containsKey('province') ? properties.get('province').getString() + ', ' : '';
        address += properties.containsKey('country') ? properties.get('country').getString() : '';
        
        return address;
    }   
}