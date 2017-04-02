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
#import <OBAKit/OBARegionStorage.h>
#import <OBAKit/OBAKit-Swift.h>

@interface OBARegionHelper ()
@property(nonatomic,copy) NSArray<OBARegionV2*> *regions;
@property(nonatomic,strong) OBARegionStorage *regionStorage;
@end

@implementation OBARegionHelper

- (instancetype)initWithLocationManager:(OBALocationManager*)locationManager modelService:(OBAModelService*)modelService {
    self = [super init];

    if (self) {
        _locationManager = locationManager;
        _modelService = modelService;
        _regionStorage = [[OBARegionStorage alloc] initWithModelFactory:modelService.modelFactory];
        _regions = [_regionStorage regions];
    }
    return self;
}

- (void)start {
    [self registerForLocationNotifications];
    [self refreshData];
}

- (void)refreshData {
    [self.modelService requestRegions:^(id responseData, NSUInteger responseCode, NSError *error) {
        if (error) {
            DDLogError(@"Error occurred while updating regions: %@", error);
            return;
        }

        self.regionStorage.regions = [responseData values];
        self.regions = [OBARegionHelper filterAcceptableRegions:[responseData values]];
        if (self.modelDAO.automaticallySelectRegion && self.locationManager.locationServicesEnabled) {
            [self setNearestRegion];
        }
        else {
            [self refreshCurrentRegionData];
        }
     }];
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

#pragma mark - Data Munging

+ (NSArray<OBARegionV2*>*)filterAcceptableRegions:(NSArray<OBARegionV2*>*)regions {
    return [regions filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(OBARegionV2 *region, NSDictionary<NSString *,id> * _Nullable bindings) {
        if (!region.active) {
            return NO;
        }

        if (!region.supportsObaRealtimeApis) {
            return NO;
        }

        return YES;
    }]];
}

@end
