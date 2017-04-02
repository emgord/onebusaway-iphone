//
//  OBARegionHelper.m
//  org.onebusaway.iphone
//
//  Created by Sebastian Kießling on 11.08.13.
//  Copyright (c) 2013 OneBusAway. All rights reserved.
//

#import <OBAKit/OBARegionHelper.h>
#import <OBAKit/OBAApplication.h>
#import <OBAKit/OBAMacros.h>
#import <OBAKit/OBALogging.h>

@interface OBARegionHelper ()
@property(nonatomic,copy) NSArray<OBARegionV2*> *regions;
@end

@implementation OBARegionHelper

- (instancetype)initWithLocationManager:(OBALocationManager*)locationManager {
    self = [super init];

    if (self) {
        _locationManager = locationManager;
        _regions = @[];
        [self registerForLocationNotifications];
    }
    return self;
}

- (void)updateRegion {
    [self.modelService requestRegions:^(id responseData, NSUInteger responseCode, NSError *error) {
        if (error && !responseData) {
            responseData = [self loadDefaultRegions];
        }
        [self processRegionData:responseData];
     }];
}

- (OBAListWithRangeAndReferencesV2*)loadDefaultRegions {
    OBAModelFactory *factory = self.modelService.modelFactory;
    NSError *error = nil;

    NSData *data = [[NSData alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"regions-v3" ofType:@"json"]];

    OBAGuard(data.length > 0) else {
        DDLogError(@"Unable to load regions from app bundle.");
        return nil;
    }

    id defaultJSONData = [NSJSONSerialization JSONObjectWithData:data options:(NSJSONReadingOptions)0 error:&error];

    if (!defaultJSONData) {
        DDLogError(@"Unable to convert bundled regions into an object. %@", error);
        return nil;
    }

    OBAListWithRangeAndReferencesV2 *references = [factory getRegionsV2FromJson:defaultJSONData error:&error];

    if (error) {
        DDLogError(@"Issue parsing bundled JSON data: %@", error);
    }

    return references;
}

- (void)processRegionData:(OBAListWithRangeAndReferencesV2*)regionData {
    OBAGuard(regionData) else {
        return;
    }

    NSArray<OBARegionV2*> *regions = regionData.values;

    self.regions = [regions filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(OBARegionV2 *region, NSDictionary<NSString *,id> * _Nullable bindings) {
        if (!region.active) {
            return NO;
        }

        if (!region.supportsObaRealtimeApis) {
            return NO;
        }

        return YES;
    }]];

    if (self.modelDAO.automaticallySelectRegion && self.locationManager.locationServicesEnabled) {
        [self setNearestRegion];
    }
    else {
        [self refreshCurrentRegionData];
    }
}

- (void)setNearestRegion {
    NSArray<OBARegionV2*> *candidateRegions = self.regionsWithin100Miles;

    // If the location manager is being lame and is refusing to
    // give us a location, then we need to proactively bail on the
    // process of picking a new region. Otherwise, Objective-C's
    // non-clever treatment of nil will result in us unexpectedly
    // selecting Tampa. This happens because Tampa is the closest
    // region to lat long point (0,0).
    if (candidateRegions.count == 0) {
        self.modelDAO.automaticallySelectRegion = NO;
        [self.delegate regionHelperShowRegionListController:self];
        return;
    }

    self.modelDAO.currentRegion = self.regions[0];
    self.modelDAO.automaticallySelectRegion = YES;
}

- (void)refreshCurrentRegionData {
    OBARegionV2 *currentRegion = self.modelDAO.currentRegion;

    if (!currentRegion && self.locationManager.hasRequestedInUseAuthorization) {
        [self.delegate regionHelperShowRegionListController:self];
        return;
    }

    for (OBARegionV2 *region in self.regions) {
        if (currentRegion.identifier == region.identifier) {
            self.modelDAO.currentRegion = region;
            break;
        }
    }
}

#pragma mark - Public Properties

- (NSArray<OBARegionV2*>*)regionsWithin100Miles {
    if (self.regions.count == 0) {
        return @[];
    }

    CLLocation *currentLocation = self.locationManager.currentLocation;

    if (!currentLocation) {
        return @[];
    }

    return [[self.regions sortedArrayUsingComparator:^NSComparisonResult(OBARegionV2 *r1, OBARegionV2 *r2) {
        CLLocationDistance distance1 = [r1 distanceFromLocation:currentLocation];
        CLLocationDistance distance2 = [r2 distanceFromLocation:currentLocation];

        if (distance1 > distance2) {
            return NSOrderedDescending;
        }
        else if (distance1 < distance2) {
            return NSOrderedAscending;
        }
        else {
            return NSOrderedSame;
        }
    }] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(OBARegionV2 *r, NSDictionary<NSString *,id> *bindings) {
        return ([r distanceFromLocation:currentLocation] < 160934); // == 100 miles
    }]];
}

#pragma mark - Lazy Loaders

- (OBAModelDAO*)modelDAO {
    if (!_modelDAO) {
        _modelDAO = [OBAApplication sharedApplication].modelDao;
    }
    return _modelDAO;
}

- (OBAModelService*)modelService {
    if (!_modelService) {
        _modelService = [OBAApplication sharedApplication].modelService;
    }
    return _modelService;
}

#pragma mark - OBALocationManager Notifications

- (void)registerForLocationNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(locationManagerDidUpdateLocation:) name:OBALocationDidUpdateNotification object:self.locationManager];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(locationManagerDidFailWithError:) name:OBALocationManagerDidFailWithErrorNotification object:self.locationManager];
}

- (void)locationManagerDidUpdateLocation:(NSNotification*)note {
    if (self.modelDAO.automaticallySelectRegion) {
        [self setNearestRegion];
    }
}

- (void)locationManagerDidFailWithError:(NSNotification*)note {
    if (!self.modelDAO.currentRegion) {
        self.modelDAO.automaticallySelectRegion = NO;
        [self.delegate regionHelperShowRegionListController:self];
    }
}

@end
