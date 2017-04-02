//
//  OBARegionHelper.h
//  org.onebusaway.iphone
//
//  Created by Sebastian Kießling on 11.08.13.
//  Copyright (c) 2013 OneBusAway. All rights reserved.
//

@import Foundation;
#import <OBAKit/OBAModelService.h>
#import <OBAKit/OBARegionV2.h>
#import <OBAKit/OBALocationManager.h>
#import <OBAKit/OBAModelDAO.h>

NS_ASSUME_NONNULL_BEGIN

@class OBARegionHelper;
@protocol OBARegionHelperDelegate <NSObject>
- (void)regionHelperShowRegionListController:(OBARegionHelper*)regionHelper;
@end

@interface OBARegionHelper : NSObject
@property(nonatomic,strong) OBALocationManager *locationManager;
@property(nonatomic,strong) OBAModelDAO *modelDAO;
@property(nonatomic,strong) OBAModelService *modelService;
@property(nonatomic,weak) id<OBARegionHelperDelegate> delegate;
@property(nonatomic,copy,readonly) NSArray<OBARegionV2*> *regionsWithin100Miles;

- (instancetype)initWithLocationManager:(OBALocationManager*)locationManager modelService:(OBAModelService*)modelService NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)start;
- (void)refreshData;
@end

NS_ASSUME_NONNULL_END
