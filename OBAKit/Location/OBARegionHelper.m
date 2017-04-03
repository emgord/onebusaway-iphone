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
@property(nonatomic,strong) NSMutableArray *regions;
@end

@implementation OBARegionHelper

- (instancetype)initWithLocationManager:(OBALocationManager*)locationManager {
    self = [super init];

    if (self) {
        _locationManager = locationManager;
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
    DDLogWarn(@"Unable to retrieve regions file. Loading default regions from the app bundle.");

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

    self.regions = [[NSMutableArray alloc] initWithArray:regionData.values];

    if (self.modelDAO.automaticallySelectRegion && self.locationManager.locationServicesEnabled) {
        [self setNearestRegion];
    }
    else {
        [self refreshCurrentRegionData];
    }
}

- (void)setNearestRegion {
    if (self.regions.count == 0) {
        return;
    }

    CLLocation *newLocation = self.locationManager.currentLocation;

    // If the location manager is being lame and is refusing to
    // give us a location, then we need to proactively bail on the
    // process of picking a new region. Otherwise, Objective-C's
    // non-clever treatment of nil will result in us unexpectedly
    // selecting Tampa. This happens because Tampa is the closest
    // region to lat long point (0,0).
    //
    // Once we're in the block, if we have a region already,
    // then do nothing and bail. Otherwise, if we don't yet have a
    // region, show the picker.
    if (!newLocation) {
        if (!self.modelDAO.currentRegion) {
            self.modelDAO.automaticallySelectRegion = NO;
            [self.delegate regionHelperShowRegionListController:self];
        }
        return;
    }

    NSMutableArray *notSupportedRegions = [NSMutableArray array];

    for (OBARegionV2 *region in self.regions) {
        if (!region.supportsObaRealtimeApis || !region.active) {
            [notSupportedRegions addObject:region];
        }
    }

    [self.regions removeObjectsInArray:notSupportedRegions];

    NSMutableArray *regionsToRemove = [NSMutableArray array];

    for (OBARegionV2 *region in self.regions) {
        CLLocationDistance distance = [region distanceFromLocation:newLocation];

        if (distance > 160934) { // 100 miles
            [regionsToRemove addObject:region];
        }
    }

    [self.regions removeObjectsInArray:regionsToRemove];

    if (self.regions.count == 0) {
        self.modelDAO.automaticallySelectRegion = NO;
        [self.delegate regionHelperShowRegionListController:self];
        return;
    }

    [self.regions sortUsingComparator:^(OBARegionV2 *region1, OBARegionV2 *region2) {
        CLLocationDistance distance1 = [region1 distanceFromLocation:newLocation];
        CLLocationDistance distance2 = [region2 distanceFromLocation:newLocation];

        if (distance1 > distance2) {
            return NSOrderedDescending;
        }
        else if (distance1 < distance2) {
            return NSOrderedAscending;
        }
        else {
            return NSOrderedSame;
        }
     }];

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
