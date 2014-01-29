{-# LANGUAGE OverloadedStrings #-}

import Control.Applicative ((<$>), (<*>), Applicative)
import qualified Data.ByteString.Lazy as L
import Data.Conduit (($$), ($=), MonadThrow (..), runResourceT, Source)
import qualified Data.Conduit.List as CL
import Data.Text (Text)
import Test.Hspec
import Text.XML.Stream.Parse (parseLBS, def)

import Cloud.AWS.Lib.Parser.Unordered

main :: IO ()
main = hspec $ do
    describe "xml parser" $ do
        it "parse normal xml" parseNormal
        it "parse normal xml by elementSink" parseNormal'
        it "parse xml which contains unordered elements" parseUnordered
        it "parse xml which contains empty list" parseEmptyList
        it "parse xml which does not contain itemSet tag" parseNotAppearItemSet
        it "cannot parse unexpected xml structure" notParseUnexpectedDataStructure
        it "ignore unexpected tag" ignoreUnexpectedTag
        it "parse top data set" parseTopDataSet
        it "parse list of text" parseList
        it "cannot parse list of text" parseListFailure
        it "parse escaped content" parseEscaped
        it "can parse ec2response-like xml" parseEC2Response
    describe "xml parser of maybe version" $
        it "parse empty xml" parseEmpty
    describe "xml parser of conduit version" $ do
        it "parse normal xml" parseTopDataSetConduit
        it "parse empty itemSet" parseEmptyItemSetConduit


data TestData = TestData
    { testDataId :: Int
    , testDataName :: Text
    , testDataDescription :: Maybe Text
    , testDataItemsSet :: [TestItem]
    } deriving (Eq, Show)

data TestItem = TestItem
    { testItemId :: Int
    , testItemName :: Text
    , testItemDescription :: Maybe Text
    , testItemSubItem :: Maybe TestItem
    } deriving (Eq, Show)

dataConv :: (MonadThrow m, Applicative m) => XmlElement -> m TestData
dataConv xml = TestData
    <$> xml .< "id"
    <*> xml .< "name"
    <*> xml .< "description"
    <*> elements "itemSet" "item" itemConv xml

itemConv :: (MonadThrow m, Applicative m) => XmlElement -> m TestItem
itemConv xml = TestItem
    <$> xml .< "id"
    <*> xml .< "name"
    <*> xml .< "description"
    <*> elementM "subItem" itemConv xml

sourceData :: MonadThrow m => L.ByteString -> Source m XmlElement
sourceData input = parseLBS def input $= elementConduit (end "data")

common :: L.ByteString -> IO TestData
common input = runResourceT $ sourceData input $$ convert (element "data" dataConv)

parseNormal :: Expectation
parseNormal = do
    d <- common input
    d `shouldBe` input'
  where
    input = L.concat
        [ "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
        , "<data>"
        , "  <id>1</id>"
        , "  <name>test</name>"
        , "  <description>this is test</description>"
        , "  <itemSet>"
        , "    <item>"
        , "      <id>1</id>"
        , "      <name>item1</name>"
        , "      <description>this is item1</description>"
        , "      <subItem>"
        , "        <id>11</id>"
        , "        <name>item1sub</name>"
        , "      </subItem>"
        , "    </item>"
        , "    <item>"
        , "      <id>2</id>"
        , "      <name>item2</name>"
        , "    </item>"
        , "  </itemSet>"
        , "</data>"
        ]
    input' = TestData
        { testDataId = 1
        , testDataName = "test"
        , testDataDescription = Just "this is test"
        , testDataItemsSet =
            [ TestItem
                { testItemId = 1
                , testItemName = "item1"
                , testItemDescription = Just "this is item1"
                , testItemSubItem = Just TestItem
                    { testItemId = 11
                    , testItemName = "item1sub"
                    , testItemDescription = Nothing
                    , testItemSubItem = Nothing
                    }
                }
            , TestItem
                { testItemId = 2
                , testItemName = "item2"
                , testItemDescription = Nothing
                , testItemSubItem = Nothing
                }
            ]
        }

parseNormal' :: Expectation
parseNormal' = do
    e <- top input
    d <- element "data" dataConv e
    d `shouldBe` input'
  where
    top i = parseLBS def i $$ elementSink
    input = L.concat
        [ "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
        , "<data>"
        , "  <id>1</id>"
        , "  <name>test</name>"
        , "  <description>this is test</description>"
        , "  <itemSet>"
        , "    <item>"
        , "      <id>1</id>"
        , "      <name>item1</name>"
        , "      <description>this is item1</description>"
        , "      <subItem>"
        , "        <id>11</id>"
        , "        <name>item1sub</name>"
        , "      </subItem>"
        , "    </item>"
        , "    <item>"
        , "      <id>2</id>"
        , "      <name>item2</name>"
        , "    </item>"
        , "  </itemSet>"
        , "</data>"
        ]
    input' = TestData
        { testDataId = 1
        , testDataName = "test"
        , testDataDescription = Just "this is test"
        , testDataItemsSet =
            [ TestItem
                { testItemId = 1
                , testItemName = "item1"
                , testItemDescription = Just "this is item1"
                , testItemSubItem = Just TestItem
                    { testItemId = 11
                    , testItemName = "item1sub"
                    , testItemDescription = Nothing
                    , testItemSubItem = Nothing
                    }
                }
            , TestItem
                { testItemId = 2
                , testItemName = "item2"
                , testItemDescription = Nothing
                , testItemSubItem = Nothing
                }
            ]
        }

parseUnordered :: Expectation
parseUnordered = do
    d <- common input
    d `shouldBe` input'
  where
    input = L.concat
        [ "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
        , "<data>"
        , "  <name>test</name>"
        , "  <itemSet>"
        , "    <item>"
        , "      <name>item1</name>"
        , "      <id>1</id>"
        , "      <subItem>"
        , "        <name>item1sub</name>"
        , "        <id>11</id>"
        , "      </subItem>"
        , "      <description>this is item1</description>"
        , "    </item>"
        , "    <item>"
        , "      <name>item2</name>"
        , "      <id>2</id>"
        , "    </item>"
        , "  </itemSet>"
        , "  <description>this is test</description>"
        , "  <id>1</id>"
        , "</data>"
        ]
    input' = TestData
        { testDataId = 1
        , testDataName = "test"
        , testDataDescription = Just "this is test"
        , testDataItemsSet =
            [ TestItem
                { testItemId = 1
                , testItemName = "item1"
                , testItemDescription = Just "this is item1"
                , testItemSubItem = Just TestItem
                    { testItemId = 11
                    , testItemName = "item1sub"
                    , testItemDescription = Nothing
                    , testItemSubItem = Nothing
                    }
                }
            , TestItem
                { testItemId = 2
                , testItemName = "item2"
                , testItemDescription = Nothing
                , testItemSubItem = Nothing
                }
            ]
        }

parseEmpty :: Expectation
parseEmpty = do
    d <- runResourceT $ sourceData input $$
        tryConvert (element "data" dataConv)
    d `shouldBe` input'
  where
    input = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
    input' = Nothing

parseEmptyList :: Expectation
parseEmptyList = do
    d <- common input
    d `shouldBe` input'
  where
    input = L.concat
        [ "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
        , "<data>"
        , "  <id>1</id>"
        , "  <name>test</name>"
        , "  <description>this is test</description>"
        , "  <itemSet>"
        , "  </itemSet>"
        , "</data>"
        ]
    input' = TestData
        { testDataId = 1
        , testDataName = "test"
        , testDataDescription = Just "this is test"
        , testDataItemsSet = []
        }

parseNotAppearItemSet :: Expectation
parseNotAppearItemSet = do
    d <- common input
    d `shouldBe` input'
  where
    input = L.concat
        [ "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
        , "<data>"
        , "  <id>1</id>"
        , "  <name>test</name>"
        , "</data>"
        ]
    input' = TestData
        { testDataId = 1
        , testDataName = "test"
        , testDataDescription = Nothing
        , testDataItemsSet = []
        }

notParseUnexpectedDataStructure :: Expectation
notParseUnexpectedDataStructure =
    common input `shouldThrow` errorCall "FromText error: no text name=name"
  where
    input = L.concat
        [ "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
        , "<data>"
        , "  <id>1</id>"
        , "  <name>"
        , "    <first>foo</first>"
        , "    <last>bar</last>"
        , "  </name>"
        , "</data>"
        ]

ignoreUnexpectedTag :: Expectation
ignoreUnexpectedTag = do
    d <- common input
    d `shouldBe` input'
  where
    input = L.concat
        [ "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
        , "<data>"
        , "  <id>1</id>"
        , "  <unexpectedTag>tag</unexpectedTag>"
        , "  <name>test</name>"
        , "  <itemSet>"
        , "    <unexpectedTag>tag</unexpectedTag>"
        , "    <unexpectedTag>tag</unexpectedTag>"
        , "  </itemSet>"
        , "  <unexpectedTag>tag</unexpectedTag>"
        , "</data>"
        ]
    input' = TestData
        { testDataId = 1
        , testDataName = "test"
        , testDataDescription = Nothing
        , testDataItemsSet = []
        }

parseTopDataSet :: Expectation
parseTopDataSet = do
    d <- runResourceT $ parseLBS def input $= mapElem $$
        convertMany (element "data" dataConv)
    d `shouldBe` input'
  where
    mapElem = elementConduit $ "dataSet" .- end "data"
    input = L.concat
        [ "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
        , "<dataSet>"
        , "  <data>"
        , "    <id>1</id>"
        , "    <name>test1</name>"
        , "    <itemSet>"
        , "    </itemSet>"
        , "    <description>this is test 1</description>"
        , "  </data>"
        , "  <data>"
        , "    <id>2</id>"
        , "    <name>test2</name>"
        , "  </data>"
        , "</dataSet>"
        ]
    input' =
        [ TestData
            { testDataId = 1
            , testDataName = "test1"
            , testDataDescription = Just "this is test 1"
            , testDataItemsSet = []
            }
        , TestData
            { testDataId = 2
            , testDataName = "test2"
            , testDataDescription = Nothing
            , testDataItemsSet = []
            }
        ]

parseTopDataSetConduit :: Expectation
parseTopDataSetConduit = do
    d <- runResourceT $ parseLBS def input $= mapElem $=
        convertConduit (element "data" dataConv) $$
        CL.consume
    d `shouldBe` input'
  where
    mapElem = elementConduit $ "dataSet" .- end "data"
    input = L.concat
        [ "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
        , "<dataSet>"
        , "  <data>"
        , "    <id>1</id>"
        , "    <name>test1</name>"
        , "    <itemSet>"
        , "    </itemSet>"
        , "    <description>this is test 1</description>"
        , "  </data>"
        , "  <data>"
        , "    <id>2</id>"
        , "    <name>test2</name>"
        , "  </data>"
        , "</dataSet>"
        ]
    input' =
        [ TestData
            { testDataId = 1
            , testDataName = "test1"
            , testDataDescription = Just "this is test 1"
            , testDataItemsSet = []
            }
        , TestData
            { testDataId = 2
            , testDataName = "test2"
            , testDataDescription = Nothing
            , testDataItemsSet = []
            }
        ]

parseEmptyItemSetConduit :: Expectation
parseEmptyItemSetConduit = do
    d <- runResourceT $ parseLBS def input $= mapElem $=
        convertConduit (element "data" dataConv) $$
        CL.consume
    d `shouldBe` input'
  where
    mapElem = elementConduit $ "dataSet" .- end "data"
    input = L.concat
        [ "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
        , "<dataSet>"
        , "</dataSet>"
        ]
    input' = []

parseList :: Expectation
parseList = do
    d <- runResourceT $ parseLBS def input $= mapElem $$
        convertMany (element "data" content)
    d `shouldBe` input'
  where
    mapElem = elementConduit $ "dataSet" .- end "data"
    input = L.concat
        [ "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
        , "<dataSet>"
        , "<data>item</data>"
        , "<data>item</data>"
        , "<data>item</data>"
        , "</dataSet>"
        ]
    input' = ["item", "item", "item"] :: [Text]

parseListFailure :: Expectation
parseListFailure = do
    runResourceT $ sourceData input $$
        convert (element "data" (content :: MonadThrow m => XmlElement -> m Text))
    `shouldThrow` anyException
  where
    input = L.concat
        [ "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
        , "<dataSet>"
        , "<data><dummy/></data>"
        , "</dataSet>"
        ]

parseEscaped :: Expectation
parseEscaped = do
    d <- runResourceT $ parseLBS def input $= mapElem $$ convert (.< "escaped")
    d `shouldBe` input'
  where
    mapElem = elementConduit $ end "escaped"
    input = "<escaped>{&quot;version&quot;:&quot;1.0&quot;,&quot;queryDate&quot;:&quot;2013-05-08T21:09:40.443+0000&quot;,&quot;startDate&quot;:&quot;2013-05-08T20:09:00.000+0000&quot;,&quot;statistic&quot;:&quot;Maximum&quot;,&quot;period&quot;:3600,&quot;recentDatapoints&quot;:[6.89],&quot;threshold&quot;:90.5}</escaped>"
    input' = "{\"version\":\"1.0\",\"queryDate\":\"2013-05-08T21:09:40.443+0000\",\"startDate\":\"2013-05-08T20:09:00.000+0000\",\"statistic\":\"Maximum\",\"period\":3600,\"recentDatapoints\":[6.89],\"threshold\":90.5}" :: Text

parseEC2Response :: Expectation
parseEC2Response = do
    (rid, d, nt) <- runResourceT $ parseLBS def (input True False) $= mapElem $$ sink
    rid `shouldBe` Just ("req-id" :: Text)
    d `shouldBe` input'
    nt `shouldBe` (Nothing :: Maybe Text)
    (rid', d', nt') <- runResourceT $ parseLBS def (input False True) $= mapElem $$ sink
    rid' `shouldBe` Nothing
    d' `shouldBe` input'
    nt' `shouldBe` Just "next-token"
  where
    mapElem = elementConduit $ "response" .=
        [ end "requestId"
        , "dataSet" .- end "data"
        , end "nextToken"
        ]
    sink = do
        rid <- tryConvert (.< "requestId")
        d <- convertMany $ element "data" dataConv
        nt <- tryConvert (.< "nextToken")
        return (rid, d, nt)
    input hasReqId hasNextToken = L.concat
        [ "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
        , "<response>"
        , if hasReqId then "  <requestId>req-id</requestId>" else ""
        , "  <dataSet>"
        , "    <data>"
        , "      <id>1</id>"
        , "      <name>test1</name>"
        , "      <itemSet>"
        , "      </itemSet>"
        , "      <description>this is test</description>"
        , "    </data>"
        , "    <data>"
        , "      <id>2</id>"
        , "      <name>test2</name>"
        , "    </data>"
        , "  </dataSet>"
        , if hasNextToken then "  <nextToken>next-token</nextToken>" else ""
        , "</response>"
        ]
    input' =
        [ TestData
            { testDataId = 1
            , testDataName = "test1"
            , testDataDescription = Just "this is test"
            , testDataItemsSet = []
            }
        , TestData
            { testDataId = 2
            , testDataName = "test2"
            , testDataDescription = Nothing
            , testDataItemsSet = []
            }
        ]
