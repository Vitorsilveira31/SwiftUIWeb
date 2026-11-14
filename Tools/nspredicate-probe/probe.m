// Evaluates a corpus of NSPredicate format strings against Apple's Foundation and records what it answers.
//
//   clang -fobjc-arc -framework Foundation probe.m -o probe && ./probe cases.json corpus.json
//
// Input: {"objects": {name: value}, "cases": [{"format", "args", "objects": [names], "vars"}]}.
// Values are JSON with typed wrappers (a plain object is an NSDictionary; an object whose only key starts with "$"
// is a wrapper): {"$i": 5} NSNumber(int64), {"$f": 1.5} NSNumber(double), {"$b": true} NSNumber(bool),
// {"$d": 0} NSDate(timeIntervalSince1970:), {"$null": 1} NSNull, {"$set": [...]} NSSet, {"$nil": 1} nil (args and
// SELF only), and JSON arrays are NSArray.
// Output: the same cases with "apple": {"parse": "ok" | "error", "format": predicateFormat, "results": [true | false |
// "exception"]} for every named object, evaluated with `evaluateWithObject:substitutionVariables:` when "vars" is given.
#import <Foundation/Foundation.h>

static id Decode(id json) {
  if ([json isKindOfClass:[NSDictionary class]]) {
    NSDictionary *dict = json;
    if (dict.count == 1) {
      NSString *key = dict.allKeys[0];
      id value = dict[key];
      if ([key isEqualToString:@"$i"]) return [NSNumber numberWithLongLong:[value longLongValue]];
      if ([key isEqualToString:@"$f"]) return [NSNumber numberWithDouble:[value doubleValue]];
      if ([key isEqualToString:@"$b"]) return [NSNumber numberWithBool:[value boolValue]];
      if ([key isEqualToString:@"$d"]) return [NSDate dateWithTimeIntervalSince1970:[value doubleValue]];
      if ([key isEqualToString:@"$null"]) return [NSNull null];
      if ([key isEqualToString:@"$nil"]) return nil;
      if ([key isEqualToString:@"$set"]) {
        NSMutableSet *set = [NSMutableSet set];
        for (id item in value) { id d = Decode(item); if (d) [set addObject:d]; }
        return set;
      }
    }
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NSString *key in dict) { id d = Decode(dict[key]); if (d) out[key] = d; }
    return out;
  }
  if ([json isKindOfClass:[NSArray class]]) {
    NSMutableArray *out = [NSMutableArray array];
    for (id item in json) { id d = Decode(item); [out addObject:d ?: [NSNull null]]; }
    return out;
  }
  if ([json isKindOfClass:[NSNumber class]]) {
    // Plain JSON numbers: integral text is an integer, anything else a double.
    NSNumber *n = json;
    if (strcmp(n.objCType, "d") == 0) return n;
    return [NSNumber numberWithLongLong:n.longLongValue];
  }
  return json;
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    NSData *data = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
    NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSMutableDictionary *objects = [NSMutableDictionary dictionary];
    for (NSString *name in root[@"objects"]) {
      id d = Decode(root[@"objects"][name]);
      objects[name] = d ?: [NSNull null];
      if (!d) objects[name] = @"$nil";
    }
    NSMutableArray *outCases = [NSMutableArray array];
    for (NSDictionary *c in root[@"cases"]) {
      NSMutableDictionary *result = [c mutableCopy];
      NSMutableArray *args = [NSMutableArray array];
      for (id a in c[@"args"] ?: @[]) { id d = Decode(a); [args addObject:d ?: [NSNull null]]; }
      NSMutableDictionary *apple = [NSMutableDictionary dictionary];
      NSPredicate *predicate = nil;
      @try {
        predicate = [NSPredicate predicateWithFormat:c[@"format"] argumentArray:args];
        apple[@"parse"] = @"ok";
        apple[@"format"] = predicate.predicateFormat;
      } @catch (NSException *e) {
        apple[@"parse"] = @"error";
        apple[@"reason"] = e.reason ?: @"";
      }
      if (predicate) {
        NSDictionary *vars = c[@"vars"];
        NSMutableDictionary *decodedVars = nil;
        if (vars) {
          decodedVars = [NSMutableDictionary dictionary];
          for (NSString *k in vars) { id d = Decode(vars[k]); decodedVars[k] = d ?: [NSNull null]; }
          @try { apple[@"substituted"] = [predicate predicateWithSubstitutionVariables:decodedVars].predicateFormat; }
          @catch (NSException *e) { apple[@"substituted"] = @"exception"; }
        }
        NSMutableArray *results = [NSMutableArray array];
        for (NSString *name in c[@"objects"] ?: @[]) {
          id object = objects[name];
          if ([object isEqual:@"$nil"]) object = nil;
          @try {
            BOOL r = decodedVars ? [predicate evaluateWithObject:object substitutionVariables:decodedVars]
                                 : [predicate evaluateWithObject:object];
            [results addObject:@(r)];
          } @catch (NSException *e) {
            [results addObject:@"exception"];
          }
        }
        apple[@"results"] = results;
      }
      result[@"apple"] = apple;
      [outCases addObject:result];
    }
    NSDictionary *out = @{@"objects": root[@"objects"], @"cases": outCases};
    NSData *json = [NSJSONSerialization dataWithJSONObject:out options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
    [json writeToFile:[NSString stringWithUTF8String:argv[2]] atomically:YES];
  }
  return 0;
}
