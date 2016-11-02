//
//  KDNControl.m
//  KDNControl
//
//  Created by Denis Koryttsev on 16/10/16.
//  Copyright © 2016 Denis Koryttsev. All rights reserved.
//

#import "QUIckControl.h"

@interface QUIckControlArrayWrapper : NSObject
-(instancetype)initWithEnumeratedObject:(id<NSFastEnumeration>)object;
@end

@interface QUIckControlArrayWrapper ()
@property (nonatomic, strong) NSMutableArray * array;
@end

@implementation QUIckControlArrayWrapper

-(instancetype)initWithEnumeratedObject:(id<NSFastEnumeration>)object {
    if (self = [super init]) {
        _array = [NSMutableArray array];
        for (id obj in object) {
            [_array addObject:obj];
        }
    }
    
    return self;
}

-(void)setValue:(id)value forKey:(NSString *)key {
    // Disable animation temporarily.
//    [CATransaction flush];
//    [CATransaction begin];
//    [CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
        if ([value conformsToProtocol:@protocol(NSFastEnumeration)]) {
            id<NSFastEnumeration> collection = value;
            short i = 0;
            for (id value in collection) {
                if (i == _array.count) return;
                [_array[i] setValue:value forKey:key];
                ++i;
            }
        } else {
            [_array setValue:value forKey:key];
        }
    // Re-enable animation.
//    [CATransaction commit];
}

-(BOOL)isEqual:(id)object {
    return self == object || [self.array isEqual:object];
}

@end

@interface QUIckControlActionTargetImp : NSObject<QUIckControlActionTarget>
@property (nonatomic, weak) QUIckControl * parentControl;
@property (nonatomic) UIControlEvents events;
@property (nonatomic, copy) void(^action)(__weak QUIckControl* control);

-(instancetype)initWithControl:(QUIckControl*)control controlEvents:(UIControlEvents)events;

@end

@implementation QUIckControlActionTargetImp

-(instancetype)initWithControl:(QUIckControl *)control controlEvents:(UIControlEvents)events {
    if (self = [super init]) {
        _events = events;
        _parentControl = control;
    }
    
    return self;
}

-(void)actionSelector:(QUIckControl*)control {
    if (self.action) self.action(self.parentControl);
}

-(void)start {
    [self.parentControl addTarget:self action:@selector(actionSelector:) forControlEvents:self.events];
}

-(void)stop {
    [self.parentControl removeTarget:self action:@selector(actionSelector:) forControlEvents:self.events];
}

@end

static NSString * const QUIckControlBoolKeyPathKey = @"boolKey";
static NSString * const QUIckControlInvertedKey = @"inverted";
static NSString * const QUIckControlTargetKey = @"target";
static NSString * const QUIckControlValueKey = @"value";
static NSString * const QUIckControlIntersectedKey = @"intersected";

// TODO: Make class contained target and him values.
@interface QUIckControl ()
@property (nonatomic) BOOL isTransitionTime;
@property (nonatomic, strong) NSMutableDictionary * stateValues;
@property (nonatomic, strong) NSMutableDictionary * states;
@property (nonatomic, strong) NSMutableDictionary * defaults;
@property (nonatomic, strong) NSMutableArray * targets;
@property (nonatomic, strong) NSMutableArray * values;
@property (nonatomic, strong) NSMutableArray * targetsDefaults;
@property (nonatomic, strong) NSMutableSet * scheduledActions;
@property (nonatomic, strong) NSPointerArray * actionTargets;
@end

@implementation QUIckControl

-(instancetype)initWithCoder:(NSCoder *)aDecoder {
    if (self = [super initWithCoder:aDecoder]) {
        [self loadStorages];
        [self registerExistedStates];
    }
    
    return self;
}

-(instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        [self loadStorages];
        [self registerExistedStates];
    }
    
    return self;
}

-(void)registerExistedStates {
    [self registerState:UIControlStateSelected forBoolKeyPath:keyPath(UIControl, selected) inverted:NO];
    [self registerState:UIControlStateHighlighted forBoolKeyPath:keyPath(UIControl, highlighted) inverted:NO];
    [self registerState:UIControlStateDisabled forBoolKeyPath:keyPath(UIControl, enabled) inverted:YES];
}

-(void)loadStorages {
    self.states = [NSMutableDictionary dictionary];
    self.stateValues = [NSMutableDictionary dictionary];
    self.defaults = [NSMutableDictionary dictionary];
    
    self.targets = [NSMutableArray array];
    self.values = [NSMutableArray array];
    self.targetsDefaults = [NSMutableArray array];
    
    self.scheduledActions = [NSMutableSet set];
    self.actionTargets = [[NSPointerArray alloc] initWithOptions:NSPointerFunctionsStrongMemory];
}

-(void)setSelected:(BOOL)selected {
    if (self.selected != selected) {
        [super setSelected:selected];
        [self applyCurrentState];
    }
}

-(void)setEnabled:(BOOL)enabled {
    if (self.enabled != enabled) {
        [super setEnabled:enabled];
        [self applyCurrentState];
    }
}

-(void)setHighlighted:(BOOL)highlighted {
    if (self.highlighted != highlighted) {
        [super setHighlighted:highlighted];
        [self applyCurrentState];
    }
}

-(void)beginTransition {
    self.isTransitionTime = YES;
}

-(void)commitTransition {
    if (!self.isTransitionTime) return;
    
    self.isTransitionTime = NO;
    [self applyCurrentState];
    for (NSNumber * action in self.scheduledActions) {
        [self sendActionsForControlEvents:[action unsignedIntegerValue]];
    }
    [self.scheduledActions removeAllObjects];
}

-(void)performTransition:(void(^)())transition {
    [self beginTransition];
    transition();
    [self commitTransition];
}

-(void)sendActionsForControlEvents:(UIControlEvents)controlEvents {
    if (self.isTransitionTime) { [self.scheduledActions addObject:@(controlEvents)]; return; }
    
    [super sendActionsForControlEvents:controlEvents];
}

-(void)removeValuesForTarget:(id)target {
    NSUInteger targetIndex = [self indexOfTarget:target];
    if (targetIndex != NSNotFound) {
        [self.targets removeObjectAtIndex:targetIndex];
        [self.values removeObjectAtIndex:targetIndex];
        [self.targetsDefaults removeObjectAtIndex:targetIndex];
    }
}

// TODO: Create possible set value for inverted state (current state not contained state)
-(void)setValue:(id)value forTarget:(id)target forKeyPath:(NSString *)key forAllStatesContained:(UIControlState)state {
    [self setValue:value forTarget:target forKeyPath:key forState:~state];
    [[[[self valuesForTarget:target] objectForKey:key] objectForKey:QUIckControlIntersectedKey] addObject:@(state)];
}

-(void)setValue:(id)value forKeyPath:(NSString *)key forState:(UIControlState)state {
    [self setValue:value forTarget:self forKeyPath:key forState:state];
}

// TODO: Create possible add values for multiple states
-(void)setValue:(id)value forTarget:(id)target forKeyPath:(NSString *)key forState:(UIControlState)state {
    NSMutableDictionary * values = [self valuesForTarget:target];
    NSMutableDictionary * valuesForKey = [values objectForKey:key];
    if (!valuesForKey && value) {
        valuesForKey = [self registerKey:key forValues:values withTarget:target];
    }
    value ? [valuesForKey setObject:value forKey:@(state)] : [valuesForKey removeObjectForKey:@(state)];
    
    if (self.state == state) {
        [self applyCurrentStateForTarget:target]; // TODO: Apply only this value
    }
}

// TODO: values should be object with this method
-(NSMutableDictionary*)registerKey:(NSString*)key forValues:(NSMutableDictionary*)values withTarget:(id)target {
    NSMutableDictionary * keyValues = [NSMutableDictionary dictionary];
    [keyValues setObject:[NSMutableArray array] forKey:QUIckControlIntersectedKey];
    [values setObject:keyValues forKey:key];
    id defaultValue = [target valueForKeyPath:key];
    if (defaultValue) {
        [[self defaultsForTarget:target] setObject:defaultValue forKey:key];
    }
    
    return keyValues;
}

-(NSMutableDictionary*)defaultsForTarget:(id)target {
    if (self == target) return self.defaults;

    return [self.targetsDefaults objectAtIndex:[self indexOfTarget:target]];
}

-(NSUInteger)indexOfTarget:(id)target {
    return [self.targets indexOfObjectPassingTest:^BOOL(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([obj isEqual:target]) {
            *stop = YES;
            return YES;
        }
        return NO;
    }];
}

-(NSMutableDictionary*)valuesForTarget:(id)target {
    if (self == target) return self.stateValues;
    
    NSUInteger index = [self indexOfTarget:target];
    if (index == NSNotFound) {
        if ([target conformsToProtocol:@protocol(NSFastEnumeration)]) {
            target = [[QUIckControlArrayWrapper alloc] initWithEnumeratedObject:target];
        }
        [self.targets addObject:target];
        [self.values addObject:[NSMutableDictionary dictionary]];
        [self.targetsDefaults addObject:[NSMutableDictionary dictionary]];
        index = self.targets.count - 1;
    }
    
    return [self.values objectAtIndex:index];
}

-(NSMutableDictionary*)valuesForExistingTarget:(id)target {
    if (self == target) return self.stateValues;
    
    NSUInteger index = [self indexOfTarget:target];
    return index != NSNotFound ? [self.values objectAtIndex:index] : nil;
}

-(void)registerState:(UIControlState)state forBoolKeyPath:(NSString*)keyPath inverted:(BOOL)inverted {
    // & UIControlStateApplication ?
    [self.states setObject:@{QUIckControlBoolKeyPathKey:keyPath, QUIckControlInvertedKey:@(inverted)} forKey:@(state)];
}

-(void)applyCurrentStateForTarget:(id)target {
    [self applyValuesForTarget:target forState:self.state];
}

-(void)applyState:(UIControlState)state {
    if (self.isTransitionTime) return;
    
    [self setNeedsDisplay];
    [self setNeedsLayout];
    
    [self applyValuesForTarget:self forState:state];
    for (id target in self.targets) {
        [self applyValuesForTarget:target forState:state];
    }
}

-(void)applyValuesForTarget:(id)target forState:(UIControlState)state {
    NSDictionary * defaults = [self defaultsForTarget:target];
    NSDictionary * values = [self valuesForExistingTarget:target];
    for (NSString * key in values) {
        id value = [self valueForKey:key fromValues:values forState:state defaults:defaults];
        [target setValue:value forKeyPath:key];
    }
}

// intersected states not corrected working if two intersected states mathed in current state and contained values for same key.
-(id)valueForKey:(NSString*)key fromValues:(NSDictionary*)values forState:(UIControlState)state defaults:(NSDictionary*)defaults {
    id keyValues = [values objectForKey:key];
    id value = [keyValues objectForKey:@(state)];
    if (!value) {
        NSArray * intersectedStates = [keyValues objectForKey:QUIckControlIntersectedKey];
        NSUInteger intersectedIndex = [intersectedStates indexOfObjectPassingTest:^BOOL(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            UIControlState intersectedState = [obj unsignedIntegerValue];
            if ((state & intersectedState) == intersectedState) {
                *stop = YES;
                return YES;
            }
            return NO;
        }];
        if (intersectedIndex != NSNotFound) {
            value = [keyValues objectForKey:@(~[[intersectedStates objectAtIndex:intersectedIndex] unsignedIntegerValue])];
        }
        if (!value) {
            value = [defaults objectForKey:key];
        }
    }
    
    return value;
}

-(id)valueForTarget:(id)target forKey:(NSString*)key forState:(UIControlState)state {
    return [self valueForKey:key fromValues:[self valuesForExistingTarget:target] forState:state defaults:[self defaultsForTarget:target]];
}

-(void)applyCurrentState {
    [self applyState:self.state];
}

-(QUIckControlActionTarget)addAction:(void (^)(__kindof QUIckControl *__weak))action forControlEvents:(UIControlEvents)events {
    QUIckControlActionTargetImp * actionTarget = [[QUIckControlActionTargetImp alloc] initWithControl:self controlEvents:events];
    actionTarget.action = action;
    [self.actionTargets addPointer:(__bridge void * _Nullable)(actionTarget)];
    
    return actionTarget;
}

-(QUIckControlActionTarget)addActionTarget:(QUIckControlActionTarget)target {
    QUIckControlActionTargetImp * sourceTarget = (QUIckControlActionTargetImp*)target;
    QUIckControlActionTargetImp * actionTarget = [[QUIckControlActionTargetImp alloc] initWithControl:self controlEvents:sourceTarget.events];
    actionTarget.action = sourceTarget.action;
    [self.actionTargets addPointer:(__bridge void * _Nullable)(actionTarget)];
    
    return actionTarget;
}

- (UIControlState)state {
    UIControlState state = UIControlStateNormal;
    
    for (NSNumber * stateValue in self.states) {
        UIControlState substate = [stateValue unsignedIntegerValue];
        NSDictionary * boolProperty = [self.states objectForKey:stateValue];
        BOOL inverted = [[boolProperty objectForKey:QUIckControlInvertedKey] boolValue];
        BOOL propertyValue = [[self valueForKeyPath:[boolProperty objectForKey:QUIckControlBoolKeyPathKey]] boolValue];
        
        if (propertyValue ^ inverted) {
            state |= substate;
        }
    }
    
    return state;
}

-(void)dealloc {
    for (QUIckControlActionTarget target in self.actionTargets) {
        [target stop];
    }
    self.actionTargets.count = 0;
}

@end
