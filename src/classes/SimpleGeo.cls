/**
@author Pat Patterson - ppatterson@salesforce.com

Force.com Toolkit for SimpleGeo

An Apex interface to the SimpleGeo API

Example usage:

// Create a client ready to use
SimpleGeo client = new SimpleGeo();

// Get context for an address - this includes latitude, longitude, 
// postal code, state etc
SimpleGeo.Context context = 
    client.getContextFromAddress('1 Market St, San Francisco, CA');

// Get context for a point (latitude, longitude)
SimpleGeo.Context context = client.getContext(37.793755, -122.395584);

// Get context for the caller's IP address
SimpleGeo.Context context = client.getContextFromIPAddress();

// Get context for an IP address
SimpleGeo.Context context = client.getContextFromIPAddress('8.8.8.8');

// Print out some information from the context
System.debug(LoggingLevel.ERROR,'lat '+context.query.latitude+
    ', lon '+context.query.longitude+', address '+context.query.address);

// These are SimpleGeo handles
String california = 'SG_2MySaPILVQG3MoXrsVehyR_37.215297_-119.663837';
String attpark = 'SG_4H2GqJDZrc0ZAjKGR8qM4D_37.778406_-122.389506';
String belltower = 
    'SG_5JkVsYK82eLj26eomFrI7S_37.795027_-122.421583@1291796505';

// Get details on a feature (identified by its handle)
SimpleGeo.Feature feature = client.getFeature(attpark);

// Print the name of the feature
System.debug(LoggingLevel.ERROR, feature.properties.get('name').getString());

// Get all the Starbucks within 0.5km of a point
SimpleGeo.Feature[] features = client.getPlaces(37.793755, -122.395584, 
    new Map<String, String>{'radius' => '0.5', 'q' => 'Starbucks'});

// Get all the Starbucks within 0.5km of an address
SimpleGeo.Feature[] features = 
    client.getPlacesNearAddress('1 Market St, San Francisco, CA', 
    new Map<String, String>{'radius' => '0.5', 'q' => 'Starbucks'});

// Get all the Starbucks within 10km of an IP address
SimpleGeo.Feature[] features = client.getPlacesNearIPAddress('8.8.8.8', 
    new Map<String, String>{'radius' => '10', 'q' => 'Starbucks'});

// Print the addresses of a list of features
for ( SimpleGeo.Feature feature: features ) {
    System.debug(LoggingLevel.ERROR, 
            feature.properties.get('address').getString());
}

// Put a record in a layer
SimpleGeo.Feature feature = new SimpleGeo.Feature();
feature.geometry = new SimpleGeo.Point(latitude, longitude);
feature.properties = new Map<String, SimpleGeo.PropertyValue>();
feature.properties.put('name', new SimpleGeo.PropertyValue(name));
client.putRecord('my.layer.name', id, feature);

// Get records close to a given point
List<Record> records = getNearby('my.layer.name', latitude, longitude, radius);

// Low level 'raw' API access - useful for returning JSON to JavaScript in a 
// Visualforce page
String url = '/0.1/records/my.layer.name/nearby/'+
    latitude+','+longitude+'.json?radius='+radius;
String json = client.sendRequestRaw(url, null, null);

 */
public with sharing class SimpleGeo {
    private String api;
    private String simpleGeoService;
    
    public SimpleGeo() {
        api = 'http://api.simplegeo.com';
        simpleGeoService = 'SimpleGeo';
    }

    public SimpleGeo(String simpleGeoService) {
        api = 'http://api.simplegeo.com';
        this.simpleGeoService = simpleGeoService;
    }

    public SimpleGeo(String simpleGeoService, String api) {
        this.api = api;
        this.simpleGeoService = simpleGeoService;
    }
    
    public class SimpleGeoException extends Exception {}
    
    public virtual class Geometry {
        public String typ;
    }
    
    public virtual class Position {
        public Double x;
        public Double y;
        public Double z;
        public Position() {         
        }
        public Position(Double lat, Double lon) {
            this.x = lon;
            this.y = lat;
        }        
    }
    
    public virtual class Point extends Geometry {
        public Point() {
            typ = 'Point';
        }
        public Point(Double lat, Double lon) {
            typ = 'Point';
            coordinates = new Position(lat, lon);
        }
        public Point(Decimal lat, Decimal lon) {
            typ = 'Point';
            coordinates = new Position((Double)lat, (Double)lon);
        }
        public Position coordinates; 
    } 
    
    public virtual class LineString extends Geometry {
        public LineString() {
            typ = 'LineString';
        }
        public Position[] coordinates; 
    }
    
    public virtual class Polygon extends Geometry {
        public Polygon() {
            typ = 'Polygon';
        }
        public LineString[] coordinates;
    }
    
    public virtual class PropertyValue {
        public Object obj;
        public List<Object> lst;
        
        public PropertyValue(Object obj) {
            this.obj = obj;
        }
        public PropertyValue(List<Object> lst) {
            this.lst = lst;
        }
        
        // I don't seem to be able to define my own toString :-(
        public String getString() {
            if ( obj != null ) {
                return String.valueOf(obj);
            }
            
            if ( lst != null ) {
                String str = '[';
                for ( Object item: lst ) {
                    str += String.valueOf(item);
                }
                str += ']';
                return str;
            }
            
            return 'null';
        }
    }
    
    public virtual class Record {
        public String typ;
        public String id;
    }
    
    public virtual class Feature extends Record {
        public Feature() {
            typ = 'Feature';
        }
        public Geometry geometry;
        public String id;
        public Map<String, PropertyValue> properties;
    }
    
    public virtual class Query {
        public Double latitude;
        public Double longitude;
    }
    
    public virtual class Classifier {
        public String category;
        public String typ;
        public String subcategory;
    }
    
    public virtual class FeatureRef {
        public String handle;
        public String name;
        public String license;
        public Double[] bounds;
        public String abbr;
        public Classifier[] classifiers;
    }
    
    public virtual class Demographics {
        public Integer metro_score;
    }

    public virtual class Context {
        public Query query;
        public Double timestamp;
        public FeatureRef[] features;
        // Weather
        public Demographics demographics;
        // Intersections
        public Feature address;
    }
    
    public virtual class Layer {
        public String name;
        public String title;
        public String description;
        public Boolean publik;
        public Long created;
        public Long updated;
    }
    
    public virtual class LayersResult {
        public Layer[] layers;
        public String nextCursor;
    }
    
    private class JsonPosition extends Position {
        public JsonPosition(Coordinates coordinates) {
            x = coordinates.arr[0].value;
            y = coordinates.arr[1].value;
            if (coordinates.arr.size() > 2) {
                z = coordinates.arr[2].value;
            }
        }
    }
    
    private class JsonLineString extends LineString {
        public JsonLineString(Coordinates coordinates) {
            Integer size = coordinates.arr.size();
            this.coordinates = new JsonPosition[size];
            for (Integer i = 0; i < size; i++) {
                this.coordinates[i] = new JsonPosition(coordinates.arr[i]);
            }
        }        
    }
    
    private class JsonPoint extends Point {
        public JsonPoint(Coordinates coordinates) {
            this.coordinates = new JsonPosition(coordinates);
        }
    }
    
    private class JsonPolygon extends Polygon {
        public JsonPolygon(Coordinates coordinates) {
            Integer size = coordinates.arr.size();
            this.coordinates = new JsonLineString[size];
            for (Integer i = 0; i < size; i++) {
                this.coordinates[i] = new JsonLineString(coordinates.arr[i]);
            }
        }
    }
    
    private class Coordinates {
        public Double value;
        public List<Coordinates> arr;
        public Coordinates() {
            arr = new List<Coordinates>();
        }
        public Coordinates(Double value) {
            this.value = value;
        }
    }
    
    private static Coordinates makeCoordinates(JSONParser parser) {
        Coordinates coordinates = new Coordinates();
        
        while (parser.nextToken() != null) {
        	JSONToken curr = parser.getCurrentToken();
            if ( curr == JSONToken.START_ARRAY ) {
                coordinates.arr.add(makeCoordinates(parser));
            } else if ( curr == JSONToken.VALUE_NUMBER_FLOAT ) {
                coordinates.arr.add(new Coordinates(parser.getDoubleValue()));
            } else if ( curr == JSONToken.END_ARRAY ) {
                return coordinates;
            } else {
                throw new SimpleGeoException('Unexpected token '+curr+' in coordinates');
            }
        }
        
        throw new SimpleGeoException('Error reading coordinates (unbalanced brackets?)');
    }
    
    private static Geometry makeGeometry(JSONParser parser) {
        String typ;
        Coordinates coordinates;
        
        // We don't know the order that type and coordinates will arrive in,
        // and coordinates' structure depends on type, so read both in then
        // create the Apex object
        while (parser.nextToken() != JSONToken.END_OBJECT) {
        	JSONToken curr = parser.getCurrentToken();
        	String text = parser.getText();
            if (curr == JSONToken.FIELD_NAME) {
                if (text == 'type') {
	                parser.nextToken();
	                typ = parser.getText();
	            } else if (text == 'coordinates') {
	                parser.nextToken();
	                coordinates = makeCoordinates(parser);
	            }
            } 
        }
        if (typ.equalsIgnoreCase('Point')) {
            return new JsonPoint(coordinates);
        } else if (typ.equalsIgnoreCase('Polygon')) {
            return new JsonPolygon(coordinates);
        } else {
            throw new SimpleGeoException('Unsupported geometry type: '+typ);
        }                
    }
    
    private static Map<String, PropertyValue> makeProperties(JSONParser parser) {
        Map<String, PropertyValue> properties = new Map<String, PropertyValue>();
        
        while (parser.nextToken() != JSONToken.END_OBJECT) {
            if (parser.getCurrentToken() == JSONToken.FIELD_NAME) {
                String key = parser.getText();
                parser.nextToken();
                if (key.equals('classifiers')) {
                    Classifier[] classifiers = new List<Classifier>();
                    while (parser.nextToken() != JSONToken.END_ARRAY) {
                        classifiers.add(new JsonClassifier(parser));                        
                    }
                    properties.put(key, new PropertyValue(classifiers));
                } else if (key.equals('tags')){
                    String[] tags = new List<String>();
                    while (parser.nextToken() != JSONToken.END_ARRAY) {
                        tags.add(parser.getText());
                    }
                    properties.put(key, new PropertyValue(tags));
                } else {
                    properties.put(key, new PropertyValue(parser.getText()));
                }
            }
        }
        
        return properties;
    }
    
    private class JsonFeature extends Feature {
        public JsonFeature(JSONParser parser) {
            while (parser.nextToken() != JSONToken.END_OBJECT) {
	        	JSONToken curr = parser.getCurrentToken();
	        	String text = parser.getText();
                if (curr == JSONToken.FIELD_NAME) {
                    if (text == 'geometry') {
	                    parser.nextToken();
	                    geometry = makeGeometry(parser);
	                } else if (text == 'type') {
	                    parser.nextToken();
	                    typ = parser.getText();
	                } else if (text == 'id') {
	                    parser.nextToken();
	                    id = parser.getText();
	                } else if (text == 'properties') {
	                    parser.nextToken();
	                    properties = makeProperties(parser);
	                }
                }
            }
        }
    }
    
    private static Feature[] makeFeatureList(JSONParser parser) {
        Feature[] features = new List<Feature>();
        while (parser.nextToken() != JSONToken.END_ARRAY) {
            features.add(new JsonFeature(parser));
        }                  
        return features;
    }
    
    private class JsonQuery extends Query {
        public JsonQuery(JSONParser parser) {
            while (parser.nextToken() != JSONToken.END_OBJECT) {
	        	JSONToken curr = parser.getCurrentToken();
	        	String text = parser.getText();
                if (curr == JSONToken.FIELD_NAME) {
                    if (text == 'latitude') {
	                    parser.nextToken();
	                    latitude = parser.getDoubleValue();
	                } else if (text == 'longitude') {
	                    parser.nextToken();
	                    longitude = parser.getDoubleValue();
	                } else if (text == 'ip') {
	                    parser.nextToken();
	                    ip = parser.getText();
	                }
                }
            }
        }
    }
    
    private class JsonClassifier extends Classifier {
        public JsonClassifier(JSONParser parser) {
            while (parser.nextToken() != JSONToken.END_OBJECT) {
	        	JSONToken curr = parser.getCurrentToken();
	        	String text = parser.getText();
                if (curr == JSONToken.FIELD_NAME) {
                    if (text == 'category') {
	                    parser.nextToken();
	                    category = parser.getText();
	                } else if (text == 'type') {
	                    parser.nextToken();
	                    typ = parser.getText();
	                } else if (text == 'subcategory') {
	                    parser.nextToken();
	                    subcategory = parser.getText();
	                }
                }
            }
        }
    }
    
    public class JsonContext extends Context {
        public JsonContext(JSONParser parser) {
            while (parser.nextToken() != JSONToken.END_OBJECT) {
	        	JSONToken curr = parser.getCurrentToken();
	        	String text = parser.getText();
                if (curr == JSONToken.FIELD_NAME) {
                    if (text == 'query') {
	                    parser.nextToken();
	                    query = new JsonQuery(parser);
	                } else if (text == 'timestamp') {
	                    parser.nextToken();
	                    timestamp = parser.getDoubleValue();
	                } else if (text == 'features') {
	                    parser.nextToken();
	                    features = new List<FeatureRef>();
	                    while (parser.nextToken() != JSONToken.END_ARRAY) {
	                        features.add(new JsonFeatureRef(parser));
	                    }
	                } else if (text == 'demographics') {
	                    parser.nextToken();
	                    demographics = new JsonDemographics(parser);
	                } else if (text == 'address') {
	                    parser.nextToken();
	                    address = new JsonFeature(parser);
	                } else {
	                    System.debug(LoggingLevel.WARN, 'JsonContext consuming unrecognized property: '+text);
	                    parser.nextToken();
	                    Integer depth = 0;
	                    do {
	                    	JSONToken curr1 = parser.getCurrentToken();
	                        if (curr1 == JSONToken.START_OBJECT || 
	                            curr1 == JSONToken.START_ARRAY) {
	                            depth++;
	                        } else if (curr1 == JSONToken.END_OBJECT ||
	                            curr1 == JSONToken.END_ARRAY) {
	                            depth--;
	                        }
	                    } while (depth > 0 && parser.nextToken() != null);
	                }
                }
            }
        }       
    }
    
    private class JsonFeatureRef extends FeatureRef {       
        public JsonFeatureRef(JSONParser parser) {
            while (parser.nextToken() != JSONToken.END_OBJECT) {
	        	JSONToken curr = parser.getCurrentToken();
	        	if (curr == JSONToken.FIELD_NAME) {
		        	String text = parser.getText();
	                if (text == 'handle') {
	                    parser.nextToken();
	                    handle = parser.getText();
	                } else if (text == 'name') {
	                    parser.nextToken();
	                    name = parser.getText();
	                } else if (text == 'license') {
	                    parser.nextToken();
	                    license = parser.getText();
	                } else if (text == 'bounds') {
	                    parser.nextToken();
	                    bounds = new List<Double>();
	                    while (parser.nextToken() != JSONToken.END_ARRAY) {
	                        bounds.add(parser.getDoubleValue());
	                    }
	                } else if (text == 'abbr') {
	                    parser.nextToken();
	                    abbr = parser.getText();
	                } else if (text == 'classifiers') {
	                    parser.nextToken();
	                    classifiers = new List<Classifier>();
	                    while (parser.nextToken() != JSONToken.END_ARRAY) {
	                        classifiers.add(new JsonClassifier(parser));
	                    }
	                } else {
	                    System.debug(LoggingLevel.WARN, 'JsonFeatureRef consuming unrecognized property: '+text);
	                    parser.nextToken();
	                    Integer depth = 0;
	                    do {
				        	JSONToken curr1 = parser.getCurrentToken();
	                        if (curr1 == JSONToken.START_OBJECT || 
	                            curr1 == JSONToken.START_ARRAY) {
	                            depth++;
	                        } else if (curr1 == JSONToken.END_OBJECT ||
	                            curr1 == JSONToken.END_ARRAY) {
	                            depth--;
	                        }
	                    } while (depth > 0 && parser.nextToken() != null);
	                }
	        	}
            }
        }
    }
    
    private class JsonDemographics extends Demographics {
        public JsonDemographics(JSONParser parser) {
            while (parser.nextToken() != JSONToken.END_OBJECT) {
	        	JSONToken curr = parser.getCurrentToken();
	        	String text = parser.getText();
                if (curr == JSONToken.FIELD_NAME){
                    if (text == 'metro_score') {
	                    parser.nextToken();
	                    metro_score = parser.getIntegerValue();
	                } else {
	                    System.debug(LoggingLevel.WARN, 'JsonDemographics consuming unrecognized property: '+text);
	                    parser.nextToken();
	                    Integer depth = 0;
	                    do {
				        	JSONToken curr1 = parser.getCurrentToken();
	                        if (curr1 == JSONToken.START_OBJECT || 
	                            curr1 == JSONToken.START_ARRAY) {
	                            depth++;
	                        } else if (curr1 == JSONToken.END_OBJECT ||
	                            curr1 == JSONToken.END_ARRAY) {
	                            depth--;
	                        }
	                    } while (depth > 0 && parser.nextToken() != null);
	                }
                }
            }
        }
    }
    
    private class JsonLayer extends Layer {
        public JsonLayer(JSONParser parser) {
            while (parser.nextToken() != JSONToken.END_OBJECT) {
	        	JSONToken curr = parser.getCurrentToken();
	        	String text = parser.getText();
                if (curr == JSONToken.FIELD_NAME) {
                    if (text == 'name') {
	                    parser.nextToken();
	                    name = parser.getText();
	                } else if (text == 'public') {
	                    parser.nextToken();
	                    publik = parser.getBooleanValue();
	                } else if (text == 'created') {
	                    parser.nextToken();
	                    created = parser.getLongValue();
	                } else if (text == 'updated') {
	                    parser.nextToken();
	                    updated = parser.getLongValue();
	                }
                }
            }
        }
    }
    
    private class JsonLayersResult extends LayersResult {
    	public JsonLayersResult(JSONParser parser) {
            while (parser.nextToken() != JSONToken.END_OBJECT) {
	        	JSONToken curr = parser.getCurrentToken();
	        	String text = parser.getText();
                if (curr == JSONToken.FIELD_NAME) {
                    if (text == 'layers') {
	                	parser.nextToken();
				        layers = new List<Layer>();
				        while (parser.nextToken() != JSONToken.END_ARRAY) {
				            layers.add(new JsonLayer(parser));
				        }                  
	                } else if (text == 'next_cursor') {
	                	parser.nextToken();
				        nextCursor = parser.getText();              
	                }
                }
            }
	    }
    }
    
    private static Record makeRecord(JSONParser parser) {
        Record record;
        
        while (parser.nextToken() != JSONToken.END_OBJECT) {
            if ((parser.getCurrentToken() == JSONToken.FIELD_NAME) &&
                (parser.getText() == 'type')) {
                parser.nextToken();
                String str = parser.getText();
                if (str.equalsIgnoreCase('feature')) {
                    record = new JsonFeature(parser);
                    throw new SimpleGeoException('Unsupported record type: '+str);
                }                
            }
        }
        throw new SimpleGeoException('Missing record type');
        
        return record;
    }
    
    public String sendRequest(String url, String method, String body) {
        HttpRequest req = new HttpRequest();
        req.setMethod((method != null) ? method : 'GET');
        req.setEndpoint(api+url);
        if (body != null) {
            System.debug('Sending body '+body);
            req.setBody(body);
        }

        OAuth oa = new OAuth();
        if(!oa.setService(simpleGeoService)) {
            System.debug(oa.message);
            return null;
        }
        oa.sign(req);
        
        System.debug('Sending request...');        
        Http h = new Http();
        HttpResponse res = h.send(req);
        System.debug('Received response ('+res.getStatusCode()+' '+res.getStatus()+')');
        
        String rbody = res.getBody().replace('\n', '');
        
        System.debug('Received body '+rbody);
        
        return rbody;
    }
    
    private String sendRequest(String url) {
        return sendRequest(url, null, null);
    }
    
    public Feature getFeature(String handle) {
        System.debug('getFeature('+handle+')');

        String url = '/1.0/features/'+handle+'.json';

        return new JsonFeature(JSON.createParser(sendRequest(url)));
    }
    
    public Context getContext(Double latitude, Double longitude) {
        System.debug('getContext('+latitude+', '+longitude+')');

        String url = '/1.0/context/'+latitude+','+longitude+'.json';

        return new JsonContext(JSON.createParser(sendRequest(url)));
    }

    public Context getContext(Decimal latitude, Decimal longitude) {
        return getContext(latitude.doubleValue(), longitude.doubleValue());
    }

    // Accept address in as a string - e.g. '1 Market St, San Francisco, CA'
    public Context getContextFromAddress(String address) {
        System.debug('getContextFromAddress('+address+')');

        String url = '/1.0/context/address.json?address="'+EncodingUtil.urlEncode(address,'UTF-8')+'"';

        return new JsonContext(JSON.createParser(sendRequest(url)));
    }
    
    public Context getContextFromIPAddress(String ip) {
        System.debug('getContextFromIPAddress('+ip+')');

        String url = '/1.0/context/'+ip+'.json';

        //return new JsonContext(sendRequest(url));
        return new JsonContext(JSON.createParser(sendRequest(url)));
    }
    
    public Context getContextFromIPAddress() {
        return getContextFromIPAddress('ip');
    }
    
    public Feature[] getPlaces(Double latitude, Double longitude, Map<String,String> arguments) {
        System.debug('getPlaces('+latitude+', '+longitude+','+arguments+')');
        
        String url = '/1.0/places/'+latitude+','+longitude+'.json';

        Boolean first = true;        
        if ( arguments != null ) {
            for ( String key: arguments.keySet() ) {
                url += ( first ) ? '?' : '&';
                first = false;
                url += key + '=' + arguments.get(key);
            }
        }

        return makeFeatureList(JSON.createParser(sendRequest(url)));
    }
    
    public Feature[] getPlaces(Double latitude, Double longitude) {
        return getPlaces(latitude, longitude, null);
    }
    
    public Feature[] getPlaces(Decimal latitude, Decimal longitude, Map<String,String> arguments) {
        return getPlaces(latitude.doubleValue(), longitude.doubleValue(), arguments);
    }
    
    public Feature[] getPlaces(Decimal latitude, Decimal longitude) {
        return getPlaces(latitude.doubleValue(), longitude.doubleValue(), null);
    }
    
    public Feature[] getPlacesNearAddress(String address, Map<String,String> arguments) {
        System.debug('getPlacesNearAddress('+address+','+arguments+')');
        
        String url = '/1.0/places/address.json?address="'+EncodingUtil.urlEncode(address,'UTF-8')+'"';

        if ( arguments != null ) {
            for ( String key: arguments.keySet() ) {
                url += '&' + key + '=' + arguments.get(key);
            }
        }

        return makeFeatureList(JSON.createParser(sendRequest(url)));       
    }
    
    public Feature[] getPlacesNearAddress(String address) {
        return getPlacesNearAddress(address, null);
    }
    
    public Feature[] getPlacesNearIPAddress(String ip, Map<String,String> arguments) {
        System.debug('getPlacesNearIPAddress('+ip+','+arguments+')');
        
        String url = '/1.0/places/'+ip+'.json';

        Boolean first = true;        
        if ( arguments != null ) {
            for ( String key: arguments.keySet() ) {
                url += ( first ) ? '?' : '&';
                first = false;
                url += key + '=' + arguments.get(key);
            }
        }

        return makeFeatureList(JSON.createParser(sendRequest(url)));       
    }
    
    public Feature[] getPlacesNearIPAddress(Map<String,String> arguments) {
        return getPlacesNearIPAddress('ip', arguments);
    }
    
    public Feature[] getPlacesNearIPAddress(String ip) {
        return getPlacesNearIPAddress(ip, null);
    }
    
    public Feature[] getPlacesNearIPAddress() {
        return getPlacesNearIPAddress('ip', null);
    }
    
    public LayersResult getLayers(Integer lim, String cursor) {
        System.debug('getLayers('+lim+','+cursor+')');
        
        String url = '/0.1/layers.json';
        String sep = '?';
        if ( lim > 0 ) {
            url += '?limit='+lim;
            sep = '&';
        }
        if ( cursor != null ) {
            url += sep+'cursor='+cursor;
        }
        
        return new JsonLayersResult(JSON.createParser(sendRequest(url)));              
    }
    
    public LayersResult getlayers(Integer lim) {
        return getLayers(lim, null);
    }

    public LayersResult getlayers() {
        return getLayers(0, null);
    }
    
    public void putLayer(Layer layer) {
        System.debug('putLayers('+layer.toString()+')');
        
        String url = '/0.1/layers/'+layer.name+'.json';

        sendRequest(url, 'PUT', JSON.serialize(layer));
    }
    
    public Record getRecord(String layer, String id) {
        System.debug('getRecord('+id+')');

        String url = '/0.1/records/'+layer+'/'+id+'.json';

        return makeRecord(JSON.createParser(sendRequest(url)));
    }

    void putGeometry(Geometry geometry, JSONGenerator gen) {
    	gen.writeStartObject();
        if ( geometry.typ != null ) {
            gen.writeStringField('type', geometry.typ);
        }
        gen.writeFieldName('coordinates');
        if (geometry.typ.equalsIgnoreCase('Point')) {
            Point p = (Point)geometry;
            gen.writeStartArray();
            gen.writeNumber(p.coordinates.x);
            gen.writeNumber(p.coordinates.y);
            gen.writeEndArray();
        } else if (geometry.typ.equalsIgnoreCase('Polygon')) {
            Polygon p = (Polygon)geometry;
            gen.writeStartArray();
            for (Integer i = 0; i < p.coordinates.size(); i++) {
	            gen.writeStartArray();
                for (Integer j = 0; j < p.coordinates[i].coordinates.size(); j++) {
		            gen.writeNumber(p.coordinates[i].coordinates[j].x);
		            gen.writeNumber(p.coordinates[i].coordinates[j].y);
                }
	            gen.writeEndArray();
            }
            gen.writeEndArray();
        } else {
            throw new SimpleGeoException('Unsupported geometry type: '+geometry.typ);
        }
    }
    
    void putProperties(Map<String, PropertyValue> properties, JSONGenerator gen) {
    	gen.writeStartObject();
        for (String key: properties.keySet()) {
            gen.writeStringField(key, properties.get(key).getString());
        }
    	gen.writeEndObject();
    }
    
    public void putRecord(String layer, String id, Record record) {
        System.debug('putRecord('+layer+', '+id+', '+record.toString()+')');
        
        String url = '/0.1/records/'+layer+'/'+id+'.json';
        
        JSONGenerator gen = JSON.createGenerator(true);
        gen.writeStartObject();
        gen.writeStringField('type', record.typ);
        if ( record.typ == 'Feature' ) {
            Feature feature = (Feature)record;
            if ( feature.geometry != null ) {
            	gen.writeFieldName('geometry');
                putGeometry(feature.geometry, gen);
            }
            if ( feature.properties != null ) {
            	gen.writeFieldName('properties');
                putProperties(feature.properties, gen);
            }
        } else {
            throw new SimpleGeoException('Unsupported record type: '+record.typ);
        }
        
        sendRequest(url, 'PUT', gen.getAsString());
    }
    
    public Record[] getNearby(String layer, Decimal lat, Decimal lon, Decimal radius) {
        System.debug('getNearby('+layer+', '+lat+', '+lon+')');
        
        String url = '/0.1/records/'+layer+'/nearby/'+lat+','+lon+'.json';
        
        if ( radius > 0 ) {
            url += '?radius='+radius;
        }
        
        return makeFeatureList(JSON.createParser(sendRequest(url)));
    }
    
    public Record[] getNearby(String layer, Decimal lat, Decimal lon) {
        return getNearby( layer, lat, lon, -1);
    }
}