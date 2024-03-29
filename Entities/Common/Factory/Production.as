// production menu
// set_string "produce sound" to override default production sound
// this.Tag("huffpuff production"); for production effects
// this.set_Vec2f("production offset", Vec2f() ); for changing where blobs appear

#include "ProductionCommon.as";
#include "ShopCommon.as";
#include "Requirements_Tech.as";
#include "CrateCommon.as";
#include "MakeFood.as";
#include "MakeSeed.as";
#include "MakeCrate.as";
#include "FireParticle.as";
#include "DebugSuite.as";

const uint OPT_TICK = 45;

void onInit( CBlob@ this )
{
	InitArrays(this);

	this.addCommandID("factory give item");
	this.addCommandID("add req");
	this.addCommandID("track blob");
	this.addCommandID("buy item");

	this.getCurrentScript().tickFrequency = OPT_TICK; // opt
}

void onTick( CBlob@ this )
{
	const u32 time = getGameTime();
    ShopItem[]@ items;
    ShopItem[]@ queue;
    
    if (!this.get( PRODUCTION_ARRAY, @items )) return;
    if (!this.get( PRODUCTION_QUEUE, @queue )) return; 

	if (this.hasTag("production paused"))
	{
		for (uint i = 0 ; i < items.length; i++)
		{
			ShopItem @item = items[i];
			item.timeCreated = time;
		}
		return;
	}
	// only if producing...
    
	for (uint i = 0 ; i < items.length; i++)
	{
	   ShopItem @item = items[i];
	   item.inProductionNow = false;

		if (item.producing)
		{  				   				
			item.inStock = hasLimitReached( this, item );
			bool reqs = hasRequirements_Tech( this.getInventory(), item.requirements, item.requirementsMissing );
			item.hasRequirements = reqs;
			item.inProductionNow = !item.inStock && item.hasRequirements;

			if (item.ticksToMake > 1)
			{
				if (item.inProductionNow)
				{
					bool found = false;
					for (uint q_step = 0; q_step < queue.length; q_step++)
						if (queue[q_step].name == item.name)
						{
							found = true;
							break;
						}
					
					if (!found)
					{
						//printf("add to queue " +item.name + " " + item.timeCreated  + " make " +  item.ticksToMake );
						queue.push_back(item);
					}
				}
				else
				{
					item.timeCreated = time;
				}
			}

		}
	}
	
	for (uint i = 0; i < queue.length; i++)
	{
		ShopItem @item = queue[i];
		
		if (i != 0) //don't progress unless we're the first one
		{
			item.timeCreated = time;
			continue;
		}
		
		if (item.inProductionNow &&
			item.ticksToMake > 1 &&	// on demand
			item.timeCreated + item.ticksToMake < time)
		{
			queue.erase(i--);
			// make item
			if (getNet().isServer())
			{
				CBlob@ blob = MakeSingleItem( this, item );						
				if (blob !is null) 
				{
					if (this.isInventoryAccessible( null ))
						this.server_PutInInventory(blob);

					// track it	   
					CBitStream params;
					params.write_u16( blob.getNetworkID() );
					this.SendCommand( this.getCommandID("track blob"), params );
				}
			}
			// make again
			item.timeCreated = time;
		}

		// effects

		if (this.hasTag("huffpuff production") && item.inProductionNow && XORRandom(5) == 0) 
		{																		 // JIT CRASHRS HERE!
			Sound::Play("/ProduceSound", this.getPosition());
			makeSmokeParticle(this.getPosition() + Vec2f(0.0f, -this.getRadius()/2.0f));
		}
	}
    
    //drop any converted vehicles
    u16[]@ ids;
	if (this.get( PRODUCTION_TRACKING_ARRAY, @ids ))
	{
		int team = this.getTeamNum();
		
		for (uint i = 0; i < ids.length; i++)
		{
			CBlob@ b = getBlobByNetworkID(ids[i]);
			if (b !is null)
			{
				if (b.getTeamNum() != team && //changed team
					b.hasTag("vehicle")) //vehicle
				{
					ids.erase(i--);
				}
			}
		}
	}
    
}	

void InitArrays( CBlob@ this )
{
	if (!this.exists(PRODUCTION_ARRAY))
	{
		ShopItem[] items;
		this.set( PRODUCTION_ARRAY, items );
	}
	if (!this.exists(PRODUCTION_QUEUE))
	{
		ShopItem[] items;
		this.set( PRODUCTION_QUEUE, items );
	}
	if (!this.exists(PRODUCTION_TRACKING_ARRAY))
	{
		u16[] ids;
		this.set( PRODUCTION_TRACKING_ARRAY, ids );
	}
}

CBlob@ MakeSingleItem( CBlob@ this, ShopItem@ item )
{
	CInventory@ inv = this.getInventory();
	CBitStream missing;
	if (item !is null && hasRequirements_Tech( inv, item.requirements, missing ))
	{
		const string blobName = item.spawnInCrate ? "crate" : item.blobName;
		Vec2f spawnPos = this.getPosition() + getRandomVelocity( 90.0f, 6.0f, 360.0f );
		if (this.exists("production offset"))
			spawnPos += this.get_Vec2f("production offset");

		if (blobName == "seed")	// MakeSeed - this needs to be done differently by some global name cache - to make standard foods, scrolls, seeds etc and not waste space of specific data
		{
			return server_MakeSeed( spawnPos, item.name );
		}
		else
		if (blobName == "food")	// MakeFood - this needs to be done differently by some global name cache - to make standard foods, scrolls, seeds etc and not waste space of specific data
		{
			//printf("MAKE FOOD " + item.name + " " + item.customData );
			server_TakeRequirements( inv, item.requirements );
			return server_MakeFood( spawnPos, item.name, item.customData );
		}
		else // everything else
		{
			CBlob@ blob = server_CreateBlobNoInit( blobName );
			if (blob !is null) 
			{
				server_TakeRequirements( inv, item.requirements );

				blob.server_setTeamNum( this.getTeamNum() );
				blob.setPosition( spawnPos );

				if (item.spawnInCrate)
				{
					SetCratePacked( blob, item.blobName, item.name, this.inventoryIconFrame );
					blob.set_u16( "msg blob", this.getNetworkID() );
				}

				item.timeCreated = getGameTime();
				blob.Init();
				return blob;
			}
		}
	}	

	return null;
}

CBlob@ Produce( CBlob@ this, const string &in name )
{
	ShopItem[]@ items; 
	if (this.get( PRODUCTION_ARRAY, @items ))
	{
		for (uint i = 0 ; i < items.length; i++)
		{
			ShopItem @item = items[i];			
			if (item.producing && item.blobName == name)
			{
				if (item.spawnInCrate)							// note: food doesn't work with crates
				{
					// check for crate in storage first
					CInventory@ inv = this.getInventory();
					for (int i = 0; i < inv.getItemsCount(); i++) 
					{
						CBlob@ invblob = inv.getItem(i);
						if (invblob.getName() == "crate" && hasPacked(invblob, item.blobName))	{ 
							return invblob;
						}
					}

					// produce the crate
					return MakeSingleItem( this, item );
				}
				else
				{
					// check for item in storage first
					CBlob@ invblob = this.server_PutOutInventory( item.blobName );
					if (invblob !is null) {
						return invblob;
					}

					// produce the item
					return MakeSingleItem( this, item );
				}
			}
		}
	}
	warn("production item " + name + " not found");
	return null;
}

void onSendCreateData( CBlob@ this, CBitStream@ stream )
{	 
	ShopSendCreateData( this, stream, PRODUCTION_ARRAY );

	u16[]@ ids; 
	if (this.get( PRODUCTION_TRACKING_ARRAY, @ids ))
	{			
		stream.write_u16( ids.length );
		for (uint i = 0; i < ids.length; i++) {
			stream.write_u16( ids[i] );
		}
	}
	else
		stream.write_u16( 0 );
}

bool onReceiveCreateData( CBlob@ this, CBitStream@ stream )
{
	InitArrays(this);

	if (!ShopReceiveCreateData( this, stream, PRODUCTION_ARRAY ))
		return false;

	u16 trackCount;
	if (!stream.saferead_u16(trackCount)) {
		warn("failed to read trackCount");
		return false;
	}

	for (uint i = 0; i < trackCount; i++)
	{					
		u16 id;
		if (!stream.saferead_u16(id)){
			return false;
		}
		this.push(PRODUCTION_TRACKING_ARRAY, id );
	}
	return true;
}

void onCommand( CBlob@ this, u8 cmd, CBitStream @params )
{
	bool isServer = getNet().isServer();
	if (isServer && cmd == this.getCommandID("factory give item"))
	{
		const u16 ID = params.read_u16();
		const string itemName = params.read_string();
		CBlob@ blob = getBlobByNetworkID( ID );
		if (blob !is null)
		{	
			CBlob@ item = Produce( this, itemName );
			if (item !is null) {
				blob.server_PutInInventory( item );
			}
		}
	}
	else
		if (isServer && cmd == this.getCommandID("add req"))
		{
			const u16 callerID = params.read_u16();
			const string itemName = params.read_string();
			CBlob@ caller = getBlobByNetworkID( callerID );
			if (caller !is null)
			{	
				// take all itemName blobs from inv and from hands of caller
				CBlob@ item = caller.server_PutOutInventory(itemName);
				if (item is null)
				{
					CBlob@ blob = caller.getCarriedBlob();
					if (blob !is null && blob.getName() == itemName)
					{	
						blob.server_DetachFromAll();
						@item = blob;
					}
				}

				while (item !is null) 
				{
					putInFood(this,item);
					
					this.server_PutInInventory( item );
					item.server_SetHealth(0.0f);
					item.Tag("dead");

					@item = caller.server_PutOutInventory(itemName);
					if (item is null)
					{
						CBlob@ blob = caller.getCarriedBlob();
						if (blob !is null && blob.getName() == itemName)
						{	
							blob.server_DetachFromAll();
							@item = blob;
						}
					}
				}
			}
		}
		else
			if (cmd == this.getCommandID("track blob"))
			{
				const u16 id = params.read_u16();
				CBlob@ blob = getBlobByNetworkID( id );
				if (blob !is null)
				{	
					// track it	   
					this.push(PRODUCTION_TRACKING_ARRAY, id );
					// sound
					if (this.exists("produce sound"))
						this.getSprite().PlaySound( this.get_string("produce sound") );
					else
						this.getSprite().PlaySound( "BombMake.ogg" );
				}
			}			
			else 
				if (isServer && cmd == this.getCommandID("buy item"))
				{
					const u16 callerID = params.read_u16();
					const u32 cost = params.read_u32();
					const string item_name = params.read_string();
					const string item = params.read_string();
					const bool inCrate = params.read_bool();

					CBlob@ caller = getBlobByNetworkID( callerID );
					//p("buy item", item_mat);


					
					if(caller !is null)
					{
						if( caller.getPlayer().getCoins() >= cost )
						{
							//caller.TakeBlob("mat_gold", coinCount * EXCHANGE_COST);
							caller.getPlayer().server_setCoins(caller.getPlayer().getCoins() - cost);
							
							Vec2f spawnPos = this.getPosition() + getRandomVelocity( 90.0f, 6.0f, 360.0f );
							if(inCrate){
								server_MakeCrate(item, item_name, this.inventoryIconFrame, this.getTeamNum(), spawnPos);
							}
							else
							{
								CBlob@ blob = server_CreateBlobNoInit( item );
								if (blob !is null) 
								{
									if (this.exists("production offset"))
										spawnPos += this.get_Vec2f("production offset");

									blob.server_setTeamNum( this.getTeamNum() );
									blob.setPosition( spawnPos );

									blob.Init();
								}
							}
							this.getSprite().PlaySound( "/ChaChing.ogg" );
						}
					}
			}
}

bool hasLimitReached( CBlob@ this, ShopItem@ item )
{
	if (item.quantityLimit == 0) { // infinite
		return false;
	}
	else
	{
		// is this item somewhere around

		uint count = 0;
							   // TODO CRATES
		u16[]@ ids; 
		if (this.get( PRODUCTION_TRACKING_ARRAY, @ids ))
		{
			for (uint i = 0; i < ids.length; i++)
			{
				CBlob@ blob = getBlobByNetworkID( ids[i] );
				if (blob !is null)
				{	  
					if (item.spawnInCrate)
					{
						if (blob.getName() == "crate" && blob.exists("packed") && blob.get_string("packed") == item.blobName)
							count++;
					}
				
					if (item.blobName == "food")
					{
						if (blob.get_string("food name") == item.name)
							count++;
					}
					else
					{
						if (blob.getName() == item.blobName)
							count++;
					}
				}
				else // remove it from the list
				{
					ids.removeAt(i);
					i--;
				}
			}
		}

	   return count >= item.quantityLimit;
	}
}

bool isInventoryAccessible( CBlob@ this, CBlob@ forBlob )
{
	return (this.hasTag("inventory access"));
}

// kitchen related

void putInFood(CBlob@ this, CBlob@ item)
{
	if (!this.exists("food")) return;
	
	string name = "amount "+item.getName();
	if (this.exists(name))
	{
		s16 food = this.get_s16("food");
		food += this.get_u8(name);
		food -= 1;
		this.set_s16("food",food);
	}
}

// add buttons to add requirement, if available

CButton@ getFactoryButton(ShopItem @item, CBlob@ this, CBlob@ caller, Vec2f buttonpos)
{
	u32 cost = getCost(item.blobName);//getCost( item.blobName );
	CBitStream params;

	params.write_u16( caller.getNetworkID() );
	params.write_u32( cost );
	params.write_string( item.name );
	params.write_string( item.blobName );
	params.write_bool( item.spawnInCrate );

	return caller.CreateGenericButton( item.iconName, buttonpos, this, this.getCommandID("buy item"), "Buy " + item.name + " : " + formatInt(cost, "") + " Coins", params );
}

u32 getCost(string item)
{
	u32 cost = 999;

	if (item == "mat_arrows"){
		cost = 15;
	}
	else if (item == "mat_waterarrows"){
		cost = 20;
	}
	else if (item == "mat_firearrows"){
		cost = 30;
	}
	else if (item == "mat_bombarrows"){
		cost = 50;
	}
	else if (item == "mat_bombs"){
		cost = 25;
	}
	else if (item == "mat_waterbombs"){
		cost = 30;
	}
	else if (item == "mine"){
		cost = 60;
	}
	else if (item == "keg"){
		cost = 120;
	}
	else if (item == "longboat"){
		cost = 120;
	}
	else if (item == "warboat"){
		cost = 250;
	}
	else if (item == "catapult"){
		cost = 80;
	}
	else if (item == "ballista"){
		cost = 150;
	}
	else if (item == "mat_bolts"){
		cost = 30;
	}


	return cost;
		
}

void GetButtonsFor( CBlob@ this, CBlob@ caller )
{
	string[] buttonsCreated;
	ShopItem[]@ prod_items;
	if (this.get( PRODUCTION_ARRAY, @prod_items ))
	{
		uint item_count = prod_items.length;
		for (uint i = 0 ; i < item_count; i++)
		{
			
			Vec2f buttonpos = Vec2f(0.0f, 0.0f);
				if(item_count > 1)
				{
					if(i == 0)
						buttonpos = Vec2f(-20.0f, 0.0f); 	
					else if(i == 1)
						buttonpos = Vec2f(20.0f, 0.0f); 	
				}
			ShopItem @item = prod_items[i];
			CButton@ button = getFactoryButton(item, this, caller, buttonpos);
			if (item !is null && item.producing)
			{
				// parse requirement stream
				string text, requiredType, name, friendlyName;
				u16 quantity = 0;
				item.requirements.ResetBitIndex();
				while (!item.requirements.isBufferEnd())
				{
					ReadRequirement( item.requirements, requiredType, name, friendlyName, quantity );
					int count = 0;
					if (caller.hasBlob( name, 1 ))
					{
						// check if not already added
						bool added = false;
						for (uint bInd = 0 ; bInd < buttonsCreated.length; bInd++)
						{
							if (buttonsCreated[bInd] == name)
							{
								added = true;
								break;
							}
						}

						if (!added)
						{
							CBitStream params;
							params.write_u16( caller.getNetworkID() );
							params.write_string( name );
							caller.CreateGenericButton( "$"+name+"$", Vec2f(-4.0f*item_count + 12.0f*i, -count), this, this.getCommandID("add req"), "Put in " + friendlyName, params );
							count++;
							buttonsCreated.push_back( name );
						}
					}
				}
			}
		}
	}  
}

// SPRITE


void onRender( CSprite@ this )
{
	CBlob@ localBlob = getLocalPlayerBlob();
	if (localBlob is null)
		return;	  

	CBlob@ blob = this.getBlob();
	Vec2f center = blob.getPosition();
	Vec2f mouseWorld = getControls().getMouseWorldPos();
	const f32 renderRadius = (blob.getRadius()) * 0.95f;		 
	bool mouseOnBlob = (mouseWorld - center).getLength() < renderRadius;
	if ( ( mouseOnBlob || (localBlob.getPosition() - center).getLength() < renderRadius ) &&
		(getHUD().hasButtons() && !getHUD().hasMenus()) 
		/*&& !localBlob.isKeyPressed(key_left) && !localBlob.isKeyPressed(key_right) &&
		!localBlob.isKeyPressed(key_up) && !localBlob.isKeyPressed(key_action1) &&
		!localBlob.isKeyPressed(key_down) && !localBlob.isKeyPressed(key_action2) */
		)
	{
		if (blob.hasTag("production paused"))
			return;

		Vec2f pos2d = blob.getScreenPos();
		CCamera@ camera = getCamera();
		f32 zoom = camera.targetDistance;
		int top = pos2d.y - zoom*blob.getHeight() + 22.0f;
		const uint margin = 7;
		Vec2f dim;
		string label = "Level 10000";
		GUI::GetTextDimensions( label , dim );
		dim.x += 2.0f * margin;
		dim.y += 2.0f * margin;
		//dim.y *= 2.0f;

		// DRAW PRODUCTION

		dim.x *= 0.8f;
		dim.y *= 0.9f;

		if (mouseOnBlob)
			blob.RenderForHUD( RenderStyle::light );

		//
		{	 
			ShopItem[]@ prod_items;
			if (blob.get( PRODUCTION_QUEUE, @prod_items ))
			{
				//DrawArrowToBlob( blob, blob.getPosition()+Vec2f(0.0f,-blob.getHeight()/4), "", false ); //draw arrow to all blobs

				// draw made items if no queue
				if (prod_items.length == 0)
					if (!blob.get( PRODUCTION_ARRAY, @prod_items ))
						return;
							  
				bool producing = false;
				u32 time = getGameTime();
				f32 initX = pos2d.x - prod_items.length*dim.x/4.0f - 12.0f;
				for (uint i = 0 ; i < prod_items.length; i++)
				{
					ShopItem @item = prod_items[i];
					if (item !is null && item.producing)
					{
						producing = true;
						const bool onDemand = item.ticksToMake == 1;
						const u32 makeTime = item.timeCreated + item.ticksToMake;
						const f32 progress = onDemand ? 1.0f : 1.0f - float(makeTime - time) / float(item.ticksToMake);

						int top2 = top;
						Vec2f iconDim;
						const string iconName = item.iconName;
						GUI::GetIconDimensions( iconName, iconDim );   

						Vec2f upperleft(initX, top2);
						f32 width = 32.0f + iconDim.x;
						Vec2f lowerright(upperleft.x + width, top2 + dim.y);
						initX += width + 1.0f;

						Vec2f mouse = getControls().getMouseScreenPos();
						const bool mouseHover = (mouse.x > upperleft.x && mouse.x < lowerright.x && mouse.y > upperleft.y && mouse.y < lowerright.y);
						const bool available = item.inStock || (onDemand && item.hasRequirements);

						if (available) {
							GUI::DrawPane( upperleft, lowerright, SColor(255, 60, 255, 30 ) );
						}
						else if (!item.hasRequirements)
						{
							GUI::DrawPane( upperleft, lowerright, SColor(255, 255, 60, 30 ) );

							if (mouseHover) // draw missing requirements   
							{
								string reqsText = item.name + "\n\nrequires\n" + getButtonRequirementsText( item.requirementsMissing, true );
								reqsText += "\n";
								reqsText += "Add materials in storage.";
								GUI::DrawText( reqsText, Vec2f(upperleft.x - 25.0f, lowerright.y + 20.0f), Vec2f(lowerright.x + 25.0f, lowerright.y + 90.0f), color_black, false, false, true );
							}								
						}
						else
						{
							GUI::DrawProgressBar( upperleft,lowerright, progress );
						}

						if (mouseHover && item.hasRequirements) // draw missing requirements   
						{
							string reqsText;  		
							//if (item.requirements.getBytesUsed() > 0)	   we have a problem with bitstream it seems to be messed up because of the uint64
							//{
								//reqsText = getButtonRequirementsText( item.requirements, false ); 
							//	reqsText += "  per unit\n\n";
							//}

							if (!available)
								reqsText += "Producing " + item.name + "...";
							else
								reqsText += item.name + (onDemand ? " available on respawn" : " limit reached.");
							GUI::DrawText( reqsText, Vec2f(upperleft.x - 25.0f, lowerright.y + 20.0f), Vec2f(lowerright.x + 25.0f, lowerright.y + 100.0f), color_black, false, false, true );

							//for drawing the arrow to the specific blob if we want that kind of HUD again
						    //DrawArrowToBlob( blob, getControls().getMouseWorldPos(), item.blobName, item.spawnInCrate );
						}	


						GUI::DrawIconByName( iconName, Vec2f(upperleft.x + 20.0f - iconDim.x, upperleft.y + (iconDim.y - dim.y)/2 - 2 ) );
					}
				}

				//GUI::DrawText( "Production", Vec2f(pos2d.x-50.0f, top-dim.y), Vec2f(pos2d.x+50.0f, top + 50.0f), color_white, true, false );
			}
		}

	}  // E
}

void DrawArrowToBlob( CBlob@ this, Vec2f start, const string &in name, bool spawnInCrate )
{
	Vec2f screenpos = getDriver().getScreenPosFromWorldPos( start );
	u16[]@ ids; 
	if (this.get( PRODUCTION_TRACKING_ARRAY, @ids ))
	{			
		for (uint i = 0; i < ids.length; i++)
		{
			CBlob@ blob = getBlobByNetworkID( ids[i] );
			if (blob !is null && (start - blob.getPosition()).getLength() > 48.0f )
			{	
				bool it = false;

				if (name == "")
				{
					it = true;
				}
				else
				{
					if (spawnInCrate)
					{
						if (blob.getName() == "crate" && blob.exists("packed") && blob.get_string("packed") == name)
							it = true;
					}

					if (blob.getName() == name)
						it = true;
				}

				if (it)
				{
					//Vec2f dim;
					//GUI::GetTextDimensions( blob.getInventoryName() , dim );
					//GUI::DrawText( blob.getInventoryName(), Vec2f(screenpos.x - dim.x/2.0f, screenpos.y - (i+1)*dim.y), Vec2f(screenpos.x + dim.x/2.0f, screenpos.y - i*dim.y), color_black, false, false, true );
					Vec2f offset(0.5f,0.5f);
					GUI::DrawSplineArrow( start+offset, blob.getPosition()+offset, color_black );
					GUI::DrawSplineArrow( start, blob.getPosition(), color_white );					
				}
			}
		}
	}
}
