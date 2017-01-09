//
//  ItemsTableViewController.m
//  KNURE TimeTable
//
//  Created by Oksana Kubiria on 08.11.13.
//  Copyright (c) 2013 Vlad Chapaev. All rights reserved.
//

#import "ItemsTableViewController.h"
#import "AddItemsTableViewController.h"
#import "TimeTableViewController.h"
#import "UIScrollView+EmptyDataSet.h"
#import "InitViewController.h"
#import "Item+CoreDataProperties.h"
#import "Lesson+CoreDataClass.h"
#import "NSDate+DateTools.h"
#import "Request.h"

@interface ItemsTableViewController() <DZNEmptyDataSetSource, URLRequestDelegate>

@property (strong, nonatomic) NSMutableArray <Item *>* datasource;

@end

@implementation ItemsTableViewController

#pragma mark - UIViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.navigationItem.title = self.headerTitle;
    
    self.tableView.emptyDataSetSource = self;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    NSPredicate *filter = [NSPredicate predicateWithFormat:@"type == %i", self.itemType];
    self.datasource = [[Item MR_findAllSortedBy:@"last_update" ascending:NO withPredicate:filter] mutableCopy];
    [self.tableView reloadEmptyDataSet];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationAutomatic];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.datasource.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Item"];
    if (!cell) {
        cell = [[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Item"];
    }
    Item *item = self.datasource[indexPath.row];
    cell.textLabel.text = item.title;
    cell.textLabel.numberOfLines = 0;
    cell.textLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightLight];
    cell.detailTextLabel.text = (item.last_update) ? [NSString stringWithFormat:@"%@: %@", NSLocalizedString(@"ItemList_Updated", nil), [item.last_update timeAgoSinceNow]] : NSLocalizedString(@"ItemList_Not_Updated", nil);
    cell.detailTextLabel.textColor = [UIColor lightGrayColor];
    
    return cell;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    
    [MagicalRecord saveWithBlockAndWait:^(NSManagedObjectContext * _Nonnull localContext) {
        Item *item = self.datasource[indexPath.row];
        NSPredicate *filter = [NSPredicate predicateWithFormat:@"item_id == %@", item.id];
        NSArray <Lesson *>*lessons = [Lesson MR_findAllWithPredicate:filter];
        for(Lesson *lesson in lessons) {
            [lesson MR_deleteEntityInContext:localContext];
        }
        [item MR_deleteEntityInContext:localContext];
        [localContext MR_saveToPersistentStoreAndWait];
    }];
    
    [self.datasource removeObjectAtIndex:indexPath.row];
    [tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationAutomatic];
    [self.tableView reloadEmptyDataSet];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewAutomaticDimension;
}

- (CGFloat)tableView:(UITableView *)tableView estimatedHeightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return tableView.rowHeight;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    //TODO: refactor
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    UIActivityIndicatorView *indicator = [[UIActivityIndicatorView alloc]initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    
    cell.accessoryView = indicator;
    Item *item = self.datasource[indexPath.row];
    [indicator startAnimating];
    
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    manager.responseSerializer.acceptableContentTypes = [NSSet setWithObject:@"text/html"];
    NSURLRequest *request = [Request getTimetable:item.id ofType:self.itemType];
    [manager GET:request.URL.absoluteString parameters:nil progress:nil success:^(NSURLSessionTask *task, id responseObject) {
        [[EventParser sharedInstance]parseTimeTable:responseObject itemID:item.id callBack:^{
            
            NSDate *lastUpdate = [NSDate date];
            
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@: %@", NSLocalizedString(@"ItemList_Updated", nil), [lastUpdate timeAgoSinceNow]];
            
            [[NSUserDefaults standardUserDefaults]setObject:@{@"id": item.id, @"title": item.title, @"type": [NSNumber numberWithInt:self.itemType]} forKey:TimetableSelectedItem];
            [[NSUserDefaults standardUserDefaults]synchronize];
            
            item.last_update = lastUpdate;
            [[item managedObjectContext] MR_saveToPersistentStoreAndWait];
            
            [indicator stopAnimating];
            
        }];
        
    } failure:^(NSURLSessionTask *operation, NSError *error) {
        cell.detailTextLabel.text = @"Не удалось обновить расписание";
        [indicator stopAnimating];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Interface_Error", @"") message:[error localizedDescription] preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Ok" style:UIAlertActionStyleCancel handler:nil];
        [alert addAction:cancel];
        [self presentViewController:alert animated:YES completion:nil];
    }];
}

#pragma mark - URLRequestDelegate

- (void)requestDidLoadItemList:(id)data ofType:(ItemType)itemType {

}

- (void)requestDidFailWithError:(NSError *)error {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Interface_Error", @"") message:[error localizedDescription] preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Ok" style:UIAlertActionStyleCancel handler:nil];
    [alert addAction:cancel];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - DZNEmptyDataSetSource

- (NSAttributedString *)titleForEmptyDataSet:(UIScrollView *)scrollView {
    NSString *text = @"Нет групп";
    
    NSDictionary *attributes = @{NSFontAttributeName: [UIFont boldSystemFontOfSize:18.0f],
                                 NSForegroundColorAttributeName: [UIColor darkGrayColor]};
    
    return [[NSAttributedString alloc] initWithString:text attributes:attributes];
}

- (NSAttributedString *)descriptionForEmptyDataSet:(UIScrollView *)scrollView {
    NSString *text = @"Нажмите значок + чтобы добавить группы, преподавателей или аудитории, расписание которых необходимо отобразить.";
    
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.lineBreakMode = NSLineBreakByWordWrapping;
    paragraph.alignment = NSTextAlignmentCenter;
    
    NSDictionary *attributes = @{NSFontAttributeName:[UIFont systemFontOfSize:14.0f],
                                 NSForegroundColorAttributeName:[UIColor lightGrayColor],
                                 NSParagraphStyleAttributeName:paragraph};
    
    return [[NSAttributedString alloc] initWithString:text attributes:attributes];
}

#pragma mark - Navigation

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:@"AddItems"]) {
        AddItemsTableViewController *controller = [segue destinationViewController];
        controller.itemType = self.itemType;
    }
}

@end
