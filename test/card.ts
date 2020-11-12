import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";

describe("Card Test Suite", () => {
    const { parseUnits } = ethers.utils;

    async function deployCardFixture() {
        const [user1, user2, user3] = await ethers.getSigners();
        const BASE_FEE = "100000000000000000";
        const GAS_PRICE_LINK = "1000000000"; // 0.000000001 LINK per gas

        const TokenFactory = await ethers.getContractFactory("Token");
        const token = await TokenFactory.deploy("Test Token", "TEST");

        const VRFCoordinatorV2MockFactory = await ethers.getContractFactory(
            "VRFCoordinatorV2Mock"
        );

        const VRFCoordinatorV2Mock = await VRFCoordinatorV2MockFactory.deploy(
            BASE_FEE,
            GAS_PRICE_LINK
        );

        const fundAmount = "1000000000000000000";
        const transaction = await VRFCoordinatorV2Mock.createSubscription();
        const transactionReceipt = await transaction.wait(1);

        const subscriptionId = ethers.BigNumber.from(transactionReceipt.events[0].topics[1]);
        await VRFCoordinatorV2Mock.fundSubscription(subscriptionId, fundAmount);

        const vrfCoordinatorAddress = VRFCoordinatorV2Mock.address;
        const keyHash = "0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc";

        const CardFactory = await ethers.getContractFactory("Card");
        const card = await CardFactory.deploy(subscriptionId, vrfCoordinatorAddress, keyHash, token.address);
        
        await VRFCoordinatorV2Mock.addConsumer(subscriptionId, card.address);

        await token.mint(user1.address, parseUnits("1000", 18));
        await token.mint(user2.address, parseUnits("1000", 18));
        await token.mint(user3.address, parseUnits("1000", 18));
        return { card, VRFCoordinatorV2Mock, token, user1, user2, user3}
    }

    describe("Create cards", () => {
        let fixture: any;
        before(async() => {
            fixture = await loadFixture(deployCardFixture);
        });

        it("Should revert if amount is not greater than 0", async () => {
            await expect(
                fixture.card.connect(fixture.user1).createCard(parseUnits("0", 18))
            ).to.be.revertedWith("Amount must be greater than 0");
        });

        it("Should revert if users do not approve their tokens", async() => {
            await expect(
                fixture.card.connect(fixture.user1).createCard(parseUnits("100", 18))
            ).to.be.revertedWith("ERC20: insufficient allowance");
        });

        it("User1 creates card and get a result", async() => {
            await fixture.token.connect(fixture.user1).approve(fixture.card.address, parseUnits("100", 18));
            
            const cardId = await fixture.card.nextCardIdForHolder(fixture.user1.address);
            await expect(
                fixture.card.connect(fixture.user1).createCard(parseUnits("100", 18))
            ).to.emit(fixture.card, "Created").withArgs(fixture.user1.address, cardId, parseUnits("100", 18));

            const requestId = await fixture.card.lastRequestId();

            await expect(
                fixture.VRFCoordinatorV2Mock.fulfillRandomWords(requestId, fixture.card.address)
            ).to.emit(fixture.card, "RequestFulfilled");
        });

        it("User2 creates card and get a result", async() => {
            await fixture.token.connect(fixture.user2).approve(fixture.card.address, parseUnits("200", 18));

            const cardId = await fixture.card.nextCardIdForHolder(fixture.user2.address);
            await expect(
                fixture.card.connect(fixture.user2).createCard(parseUnits("200", 18))
            ).to.emit(fixture.card, "Created").withArgs(fixture.user2.address, cardId, parseUnits("200", 18));

            const requestId = await fixture.card.lastRequestId();

            await expect(
                fixture.VRFCoordinatorV2Mock.fulfillRandomWords(requestId, fixture.card.address)
            ).to.emit(fixture.card, "RequestFulfilled")
        });

        it("User3 creates card and get a result", async() => {
            await fixture.token.connect(fixture.user3).approve(fixture.card.address, parseUnits("300", 18));

            const cardId = await fixture.card.nextCardIdForHolder(fixture.user3.address);
            await expect(
                fixture.card.connect(fixture.user3).createCard(parseUnits("300", 18))
            ).to.emit(fixture.card, "Created").withArgs(fixture.user3.address, cardId, parseUnits("300", 18));

            const requestId = await fixture.card.lastRequestId();

            await expect(
                fixture.VRFCoordinatorV2Mock.fulfillRandomWords(requestId, fixture.card.address)
            ).to.emit(fixture.card, "RequestFulfilled");
        });
    });

    describe("Banish cards", () => {
        let fixture: any;
        before(async() => {
            fixture = await loadFixture(deployCardFixture);
        });

        it("Should revert if the card does not exist", async() => {
            await expect(
                fixture.card.connect(fixture.user1).banishCard(0)
            ).to.be.rejectedWith("This card does not exist");
        });

        it("Should revert if there is no sufficient token amount", async() => {
            await fixture.token.connect(fixture.user1).approve(fixture.card.address, parseUnits("100", 18));
            await fixture.card.connect(fixture.user1).createCard(parseUnits("100", 18));
            const requestId = await fixture.card.lastRequestId();
            await fixture.VRFCoordinatorV2Mock.fulfillRandomWords(requestId, fixture.card.address);
            // 2 days later
            await time.increase(2 * 24 * 3600);
            await expect(
                fixture.card.connect(fixture.user1).banishCard(0)
            ).to.be.rejectedWith("Insufficient token amount");
        });

        it("User1 banishes his first card successfully", async() => {
            await fixture.token.mint(fixture.card.address, parseUnits("10000", 18));
            await expect(
                fixture.card.connect(fixture.user1).banishCard(0)
            ).to.emit(fixture.card, "Banished");
        });
    });
});
