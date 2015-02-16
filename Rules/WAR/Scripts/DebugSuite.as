// p prints out a value straight to the console
// pp takes in a string title and a name, and then prints them together
// c prints out a value to the chat client
// cc takes in a string title and a name, and then prints them out the chat client
// All functions will take in CBlobs, ints, floats, and Vec2fs

void p(CBlob@ blob){
	print(blob.getName());
}

void p(int toPrint){
	print(formatInt(toPrint, ""));
}

void p(f32 toPrint){
	print(formatFloat(toPrint, "", 0, 2));
}

void p(Vec2f toPrint){
	string x = formatFloat(toPrint.x, "", 0, 2);
	string y = formatFloat(toPrint.y, "", 0, 2);

	print("x: " + x + " y: " + y);
}

void p(string toPrint){
	print(toPrint);
}

void p(string title, CBlob@ blob){
	print(title + ": " + blob.getName());
}

void p(string title, int toPrint){
	string num = formatInt(toPrint, "");

	print(title + ": " + num);
}

void p(string title, f32 toPrint){
	string num = formatFloat(toPrint, "", 0, 2);

	print(title + ": " + num);
}

void p(string title, Vec2f toPrint){
	string x = formatFloat(toPrint.x, "", 0, 2);
	string y = formatFloat(toPrint.y, "", 0, 2);

	print(title + " = x: " + x + " y: " + y);
}

void p(string title, string toPrint){
	print(title + ": " + toPrint);
}

void p(bool boolean){
	if(boolean)
		print("true");
	else
		print("false");
}

void p(string title, bool boolean){
	if(boolean)
		print(title + ": true");
	else
		print(title + ": false");
}

void c(CBlob@ blob){
	client_AddToChat(blob.getName());
}

void c(int toPrint){
	client_AddToChat(formatInt(toPrint, ""));
}

void c(f32 toPrint){
	client_AddToChat(formatFloat(toPrint, "", 0, 2));
}

void c(Vec2f toPrint){
	string x = formatFloat(toPrint.x, "", 0, 2);
	string y = formatFloat(toPrint.y, "", 0, 2);

	client_AddToChat("x: " + x + " y: " + y);
}

void c(string title, CBlob@ blob){
	client_AddToChat(title + ": " + blob.getName() );
}

void c(string title, int toPrint){
	client_AddToChat(title + ": " + formatInt(toPrint, ""));
}

void c(string title, f32 toPrint){
	client_AddToChat(title + ": " + formatFloat(toPrint, "", 0, 2));
}

void c(string title, Vec2f toPrint){
	string x = formatFloat(toPrint.x, "", 0, 2);
	string y = formatFloat(toPrint.y, "", 0, 2);

	client_AddToChat(title + " = " + "x:" + x + " y:" + y);
}


