
// must include :
// code/metadata-extractor-2.19.0.jar
// code/xmpcore-6.1.8.jar

import com.drew.imaging.*;
import com.drew.metadata.*;
import com.drew.metadata.exif.*;
import processing.sound.*;

import javax.sound.midi.*;

ArrayList<String> files = new ArrayList<String>();
ArrayList<PImage> images = new ArrayList<PImage>();

String[] packNames;
int currentPackIndex = -1;

int slideShowType = 0;

ArrayList<CopyRectangle> copyRectangles = new ArrayList<CopyRectangle>();

ArrayList<String> text = new ArrayList<String>();

PFont font;

float lastTap=0;
float tempoMs = 1000;
double lastMs = 0;

boolean displayLoadBar = false;// displays a loading bar showing the time between slideshow pages

String phrase = "";

PImage[] symIm = new PImage[4];

int displayMode = 0;
// 0 noir + phrases
// 1 generative slideshow
// 2 smear
// 3 symmetries
// 4 sorting

AudioIn input;
Amplitude rms;
float audioSum = 0, smoothingFactor = 0.2;
float midiMod = 0;
int modulationSource = 0;
// 0 = autonoous
// 1 = audio
// 2 = midi

MidiDevice device;
Transmitter transmitter;
Receiver receiver;

boolean videoCaptured = false;
int videoFrames = 0;

int preloadingCue = 5;// number of images to preload (higher is more diversity but longer loading times and risks)

int colorMode = 0;

boolean freezeEffect = false;

int currentLineText = 0;

boolean displayText = true;
boolean displayTextBackground = true;

void setup() {
  fullScreen();
  frameRate(60);
  font = loadFont(dataPath("files/CourierPrime-150.vlw"));
  packNames = getSubfolders(dataPath("photos"));
  String[] textFiles = getAllFilesFrom(dataPath("textes"));
  for (String tF : textFiles) {
    String[] lines = loadStrings(tF);
    for (String l : lines) {
      text.add(l);
    }
  }
  input = new AudioIn(this, 0);
  input.start();
  rms = new Amplitude(this);
  rms.input(input);

  println("Available MIDI Devices:");
  MidiDevice.Info[] infos = MidiSystem.getMidiDeviceInfo();
  for (int i = 0; i < infos.length; i++) {
    println("["+i+"] " + infos[i].getName());
  }

  try {
    device = MidiSystem.getMidiDevice(infos[9]); // Try first MIDI device
    device.open();
    transmitter = device.getTransmitter();
    receiver = new MidiInputReceiver();
    transmitter.setReceiver(receiver);
    println("MIDI Device Opened: " + device.getDeviceInfo().getName());
  }
  catch (Exception e) {
    println("Error: " + e);
  }

  loadPack(-1);
  shiftImageList();
  noStroke();
  background(0);
}

void draw() {

  audioSum += (rms.analyze() - audioSum) * smoothingFactor;

  if (displayMode==0) {
    // black background + text after first iteration
  }

  if (displayMode==1) {
    // slideshow mode
    if ((millis()-lastMs)>=tempoMs) {
      displayComposition();
    }
    if (displayLoadBar) {
      fill(0xFF);
      rect(0, 0, (float) ((millis() - lastMs) / tempoMs) * width, 10);
    }
  }

  if (displayMode==2) {
    // smear effect
    for (CopyRectangle cR : copyRectangles) cR.draw();
    if (videoCaptured) captureVideoFrame();
  }

  if (displayMode == 3) {
    // symmetries
    float excenter = map(sin((float)millis()/1000), -1, 1, 0, 1) * min(symIm[0].width-width/2, symIm[0].height-height/2);
    if (modulationSource==1) excenter = pow(audioSum, 0.5) * min(symIm[0].width-width/2, symIm[0].height-height/2);
    if (modulationSource==2) excenter = pow(midiMod, 0.5) * min(symIm[0].width-width/2, symIm[0].height-height/2);

    int cropW = ceil((float) width / 2 + excenter);
    int cropH = ceil((float) height / 2 + excenter);
    int centerX = symIm[0].width / 2;
    int centerY = symIm[0].height / 2;

    // Crop each quadrant dynamically
    PImage[] croppedImages = new PImage[4];
    for (int i = 0; i < 4; i++) croppedImages[i] = symIm[i].get(centerX - cropW / 2, centerY - cropH / 2, cropW, cropH);

    // Place images correctly so they expand symmetrically from the center
    background(0);
    image(croppedImages[0], width / 2 - cropW, height / 2 - cropH);
    image(croppedImages[1], width / 2, height / 2 - cropH);
    image(croppedImages[2], width / 2 - cropW, height / 2);
    image(croppedImages[3], width / 2, height / 2);
    if (videoCaptured) captureVideoFrame();
  }

  if (displayMode == 4) {
    loadPixels();
    int nbIterations = 50;
    if (modulationSource == 1) nbIterations = floor((float)nbIterations*audioSum);
    if (modulationSource == 2) nbIterations = floor((float)nbIterations*midiMod);
    for (int i = 0; i < nbIterations; i++) {
      int x = floor(random(width));
      int yA = constrain(floor(random(-height / 2, height - 2)), 0, height);
      int yB = constrain(floor(random(yA + 1, height * 1.5)), 0, height);
      int len = yB - yA;
      color[] cs = new color[len];
      int pixelIndex = yA * width + x;
      for (int y = 0; y < len; y++) {
        cs[y] = pixels[pixelIndex + y * width];
      }
      if (!freezeEffect) sortColorsByBrightness(cs); // Sort brightness
      for (int y = 0; y < len; y++) {
        pixels[pixelIndex + y * width] = cs[y];
      }
    }
    updatePixels();
  }

  if (!midiInteraction.equals("")) {
    interact(midiInteraction);
    midiInteraction="";
  }
}

void keyPressed() {
  if (key=='a') interact("black");
  if (key=='z') interact("slideshows");
  if (key=='e') interact("smear");
  if (key=='r') interact("symmetries");
  if (key=='t') interact("sorting");
  if (key=='y') interact("displayText");
  if (key=='u') interact("displayTextBackground");
  if (key=='i') interact("modulationSource");
  if (key=='v') interact("videoRec");
  if (key=='p') interact("packs");
  if (key=='l') interact("reload");
  if (key=='c') interact("screenshot");
  if (key=='b') interact("colorMode");
  if (key=='f') interact("freezeEffect");
}

void interact(String command) {
  println("command : "+command);
  if (command.equals("black")) {// black then text
    if (displayMode!=0) phrase= "";
    else phrase = text.get(currentLineText);
    currentLineText = (currentLineText+1)%text.size();
    displayMode = 0;
    background(0);
    fill(0xFF);
    textAlign(CENTER, CENTER);
    textSize(100);
    textFont(font, 100);
    text(phrase, 0, 0, width, height);
    if (videoCaptured) captureVideoFrame();
  }
  if (command.equals("slideshows")) {// slideshows
    displayMode = 1;
    tempoMs = millis()-lastTap;
    lastTap = millis();
    lastMs = millis();
    displayComposition();
  }
  if (command.equals("smear")) {// smear effect
    displayMode = 2;
    copyRectangles.clear();
    while (copyRectangles.size()<50) addNewCopyRectangle();
  }
  if (command.equals("symmetries")) {// symmetries
    displayMode = 3;
    prepareSymImages();
  }
  if (command.equals("sorting")) {// sorting
    displayMode = 4;
  }
  if (command.equals("displayText")) {
    displayText ^= true;
  }
  if (command.equals("displayTextBackground")) {
    displayTextBackground ^= true;
  }
  if (command.equals("modulationSource")) {// enable/disable audio input or midi mod
    modulationSource = (modulationSource+1)%3;
    println("modulation source : "+modulationSource);// 0 = auto, 1 = audio, 2 = midi
  }
  if (command.equals("videoRec")) {// enable/disable video recording
    videoCaptured ^= true;
    println("videoCaptured : "+videoCaptured);
  }
  if (command.equals("packs")) { // switch between packs
    currentPackIndex++;
    if (currentPackIndex>=packNames.length) currentPackIndex=-1;
    if (currentPackIndex==-1) println("current pack : (all packs)");
    else println("current pack : "+packNames[currentPackIndex]);
    loadPack(currentPackIndex);
  }
  if (command.equals("reload")) { // reload image buffer based on current pack
    println("reload images");
    images.clear();
    shiftImageList();
  }
  if (command.equals("screenshot")) {// take a single screenshot
    int nbExports = 0;
    String filePath;
    do filePath = dataPath("results/result" + nf(nbExports++, 6) + ".png");
    while (new File(filePath).exists());
    save(filePath);
  }
  if (command.equals("colorMode")) {// switch color mode
    colorMode=(colorMode+1)%4;
    println("colorMode : "+colorMode);// 0 = normal, 1 = black and white, 2 = bitmap, 3 = arbitrary
  }
  if (command.equals("freezeEffect")) {// freeze effect
    freezeEffect ^= true;
    println("freeze effect : "+freezeEffect);
  }
}

void displayComposition() {
  if (displayMode==1) {

    if (images.size()==0) return;

    if (slideShowType==0) {
      background(0xFF);
      PImage imL = images.get(0);
      PImage imR = images.get(1);
      PVector interestL = new PVector(random((float)imL.width*0.3, (float)imL.width*0.7), random((float)imL.height*0.3, (float)imL.height*0.7));
      PVector interestR = new PVector(random((float)imR.width*0.3, (float)imR.width*0.7), random((float)imR.height*0.3, (float)imR.height*0.7));
      if (random(1)<0.8) interestL = new PVector((float)imL.width*1/4, (float)imL.height*1/2);
      if (random(1)<0.8) interestR = new PVector((float)imR.width*3/4, (float)imR.height*1/2);
      PImage croppedL = cropAndResize(imL, interestL.x, interestL.y, (float)width/2, (float)height);
      PImage croppedR = cropAndResize(imR, interestR.x, interestR.y, (float)width/2, (float)height);
      image(croppedL, (float)width*0/2, 0, (float)width*1/2, (float)height);
      image(croppedR, (float)width*1/2, 0, (float)width*1/2, (float)height);
      PVector textEPos = new PVector((float)floor(random(2))*width/2, (float)floor(random(1))*height/1);
      PVector textESiz = new PVector((float)width/2, (float)height/1);
      displayTextAt(textEPos, textESiz);
    }

    if (slideShowType==1) {
      int nbImToUse = floor(min(images.size(), random(1, 10)));
      int nbX = floor(random(1, 8));
      int nbY = floor(random(1, 5));
      for (int x=0; x<nbX; x++) {
        for (int y=0; y<nbY; y++) {
          PImage im = images.get(floor(random(nbImToUse)));
          PVector interest = new PVector(random((float)im.width*0.3, (float)im.width*0.7), random((float)im.height*0.3, (float)im.height*0.7));
          if (random(1)<0.5) interest = new PVector((float)im.width*((float)x+0.5)/(float)nbX, (float)im.height*((float)y+0.5)/(float)nbY);
          if (random(1)<0.2) interest = getPossibleDynamicPoint(im);
          PImage cropped = cropAndResize(im, interest.x, interest.y, (float)width/nbX, (float)height/nbY);
          cropped = subCrop(cropped, random(random(3))+1);
          image(cropped, x*(float)width/nbX, y*(float)height/nbY, (float)width/nbX, (float)height/nbY);
        }
      }
      boolean oneMoreText = true;
      while (oneMoreText) {
        int textIX1 = floor(random(nbX));
        int textIY1 = floor(random(nbY));
        int textIX2 = floor(random(random((nbX+1)-(textIX1+1)))+(textIX1+1));
        int textIY2 = floor(random(random((nbY+1)-(textIY1+1)))+(textIY1+1));
        PVector textEPos = new PVector((float)textIX1*width/nbX, (float)textIY1*height/nbY);
        PVector textESiz = new PVector(((float)textIX2-textIX1)*(float)width/nbX, ((float)textIY2-textIY1)*(float)height/nbY);
        displayTextAt(textEPos, textESiz);
        oneMoreText=(nbX>1 && nbY>1 && random(1)<0.5 && (textIX2-textIX1)==1 && (textIY2-textIY1)==1);
      }
    }

    if (slideShowType==2) {
      int nbImToUse = 1;
      int nbX = floor(random(3, 8));
      int nbY = floor(random(3, 6));
      if (random(1)<0.3) {
        if (random(1)<0.5) nbX=1;
        else nbY=1;
      }

      float maxZoom = random(1, 3);
      float lerpToCenter = random(0, 1);
      for (int x=0; x<nbX; x++) {
        for (int y=0; y<nbY; y++) {
          PImage im = images.get(floor(random(random(nbImToUse))));
          PVector interest = new PVector((float)im.width*((float)x+0.5)/(float)nbX, (float)im.height*((float)y+0.5)/(float)nbY);
          interest = PVector.lerp(interest, new PVector((float)width/2, (float)height/2), lerpToCenter);
          if (random(1)<0.2) interest = getPossibleDynamicPoint(im);
          PImage cropped = cropAndResize(im, interest.x, interest.y, (float)width/nbX, (float)height/nbY);
          float normX = (nbX==1)?0.5:map(x, 0, nbX - 1, -1, 1);
          float normY = (nbY==1)?0.5:map(y, 0, nbY - 1, -1, 1);
          float distanceFromCenter = max(abs(normX), abs(normY));
          float zoomValue = 1 - distanceFromCenter;
          zoomValue = map(zoomValue, 0, 1, 1, maxZoom);
          cropped = subCrop(cropped, zoomValue);
          image(cropped, x*(float)width/nbX, y*(float)height/nbY, (float)width/nbX, (float)height/nbY);
        }
      }
      if (random(1)<0.5) {
        PVector textEPos = new PVector(0, 0);
        PVector textESiz = new PVector(width, height);
        displayTextAt(textEPos, textESiz);
      }
    }

    if (slideShowType==3) {
      int nbImToUse = floor(min(images.size(), 3));
      PImage im = images.get(floor(random(random(nbImToUse))));
      PImage im2 = images.get(floor(random(random(nbImToUse))));
      PVector interest = new PVector(random((float)im.width*0.3, (float)im.width*0.7), random((float)im.height*0.3, (float)im.height*0.7));
      if (random(1)<0.2) interest = getPossibleDynamicPoint(im);
      PImage croppedA = cropAndResize(im, interest.x, interest.y, (float)width, (float)height);
      PVector smallSize = new PVector(random((float)width/5, (float)width/2), random((float)height/5, (float)height/2));
      PVector smallPosition = new PVector(random(width-smallSize.x), random(height-smallSize.y));
      PImage croppedB = cropAndResize(im2, interest.x, interest.y, smallSize.x, smallSize.y);
      image(croppedA, 0, 0, width, height);
      image(croppedB, smallPosition.x, smallPosition.y, smallSize.x, smallSize.y);
      PVector textESiz = new PVector(random((float)width/3, (float)width/2), random((float)height/5, (float)height/4));
      PVector textEPos = new PVector(random(width-textESiz.x), random(height-textESiz.y));
      displayTextAt(textEPos, textESiz);
    }

    thread("shiftImageList");
    slideShowType = (slideShowType+1)%4;
    if (videoCaptured) captureVideoFrame();
  }

  lastMs = millis();
}

void loadPack(int index) {
  files.clear();
  if (index==-1) {
    for (String pack : packNames) {
      String[] fs = getAllFilesFrom(dataPath("photos/" + pack));
      for (String f : fs) files.add(f);
    }
  } else {
    String[] fs = getAllFilesFrom(dataPath("photos/" + packNames[index]));
    for (String f : fs) files.add(f);
  }
}

void captureVideoFrame() {
  int nbExports = 0;
  String filePath;
  do filePath = dataPath("results/video/result" + nf(nbExports++, 6) + ".png");
  while (new File(filePath).exists());
  save(filePath);
}

void displayTextAt(PVector textEPos, PVector textESiz) {
  float borderMargins = 3;
  float tS = map(textESiz.x, 0, width, 20, 150);
  textAlign(CENTER, CENTER);
  float[] bgBrightness = averageBrightness(get(floor(textEPos.x), floor(textEPos.y), floor(textESiz.x), floor(textESiz.y))) ;
  color textColor = color(0xFF);
  if (lerp(bgBrightness[0], bgBrightness[2], 0.5)<100) fill(0xFF);
  else if (lerp(bgBrightness[0], bgBrightness[1], 0.5)>200) fill(0);
  else {
    if (random(1)<0.8) {
      fill(0);
      if (displayTextBackground) rect(textEPos.x, textEPos.y, textESiz.x, textESiz.y);
      textColor = 0xFF;
    } else {
      fill(0xFF);
      if (displayTextBackground) rect(textEPos.x, textEPos.y, textESiz.x, textESiz.y);
      textColor = color(0);
    }
  }
  textMode(CORNER);
  String phrase = text.get(currentLineText);
  currentLineText = (currentLineText+1)%text.size();
  PImage im = getTextAsImage(phrase, textESiz.x-borderMargins*2, textESiz.y-borderMargins*2, tS, textColor);
  if (displayText) image(im, textEPos.x+borderMargins, textEPos.y+borderMargins);
}

PImage getTextAsImage(String phrase, float w, float h, float textSize, color textColor) {
  int h2=-1;
  // if text exceeds h, reduce the text size until the text fits in the PGraphics expected height
  float heightScale = 3;
  PGraphics pg = createGraphics((int)w, (int)(h*heightScale));
  int y = 0, y2 = 0;
  while (h2>h || h2==-1) {
    textSize *= 0.9;
    // disiplay the text at the right size on a taller PGraphics
    pg = createGraphics((int)w, (int)(h*heightScale));
    pg.beginDraw();
    pg.textSize(textSize);
    pg.textFont(font, textSize);
    pg.textAlign(CENTER, CENTER);
    pg.fill(textColor);
    pg.text(phrase, 0, 0, w, h*heightScale);
    pg.endDraw();
    PImage im = pg.get();
    im.loadPixels();
    y = 0;
    while (y<im.height) {
      boolean empty = true;
      for (int x=0; x<im.width; x++) {
        if (im.pixels[y*im.width+x]!=0) {
          empty = false;
          break;
        }
      }
      if (!empty) {
        y--;
        break;
      }
      y++;
    }
    y2 = im.height-1;
    while (y2>=0) {
      boolean empty = true;
      for (int x=0; x<im.width; x++) {
        if (im.pixels[y2*im.width+x]!=0) {
          empty = false;
          break;
        }
      }
      if (!empty) {
        y2++;
        break;
      }
      y2--;
    }
    h2 = y2-y;
  }
  // crop and return the picture at the right size (h)
  int alternate=0;
  while (y2-y<h) {
    if (alternate==0) y2++;
    if (alternate==1) y--;
    alternate=(alternate+1)%2;
  }
  return pg.get(0, y, floor(w), floor(y2-y));
}

void shiftImageList() {
  synchronized(images) {
    if (images.size()>0)images.remove(0);
    while (images.size()<preloadingCue) {
      try {
        PImage im = loadImageOrient(files.get(floor(random(files.size()))));
        im = convertImage(im, colorMode);
        if (im!=null) images.add(im);
      }
      catch (Exception e) {
        println(e);
      }
    }
  }
}

void prepareSymImages() {
  PImage chosenIm = images.get(floor(random(images.size())));
  float centerW = (float)chosenIm.width * random(0.4, 0.6);
  float centerH = (float)chosenIm.height * random(0.4, 0.6);
  float emboss = random(1, 2);
  PImage cropped = cropAndResize(chosenIm, centerW, centerH, width*emboss, height*emboss);
  symIm = new PImage[]{
    cropped, // Top-left (original)
    mirrorImage(cropped, true, false), // Top-right (mirrored X)
    mirrorImage(cropped, false, true), // Bottom-left (mirrored Y)
    mirrorImage(cropped, true, true)   // Bottom-right (mirrored X + Y)
  };
  thread("shiftImageList");
}

PImage mirrorImage(PImage img, boolean flipX, boolean flipY) {
  PImage mirrored = createImage(img.width, img.height, RGB);
  mirrored.loadPixels();
  img.loadPixels();

  for (int y = 0; y < img.height; y++) {
    for (int x = 0; x < img.width; x++) {
      int srcX = flipX ? (img.width - 1 - x) : x;
      int srcY = flipY ? (img.height - 1 - y) : y;
      mirrored.pixels[y * img.width + x] = img.pixels[srcY * img.width + srcX];
    }
  }

  mirrored.updatePixels();
  return mirrored;
}

PImage cropAndResize(PImage im, float centerW, float centerH, float outputW, float outputH) {
  float WHratio = outputW / outputH;

  // Compute maximum cropping region within image boundaries
  float maxHalfWSize = min(centerW, im.width - centerW);
  float maxHalfHSize = min(centerH, im.height - centerH);

  // Adjust to maintain the correct aspect ratio
  if (maxHalfWSize / maxHalfHSize > WHratio) {
    maxHalfWSize = maxHalfHSize * WHratio;
  } else {
    maxHalfHSize = maxHalfWSize / WHratio;
  }

  // Compute top-left corner of the cropping region
  int x = round(centerW - maxHalfWSize);
  int y = round(centerH - maxHalfHSize);
  int cropWidth = round(2 * maxHalfWSize);
  int cropHeight = round(2 * maxHalfHSize);

  // Ensure crop dimensions stay within bounds
  x = constrain(x, 0, im.width - cropWidth);
  y = constrain(y, 0, im.height - cropHeight);

  // Crop the image
  PImage cropped = im.get(x, y, cropWidth, cropHeight);

  // Resize to the requested output dimensions
  PImage output = createImage((int) outputW, (int) outputH, RGB);
  output.copy(cropped, 0, 0, cropped.width, cropped.height, 0, 0, output.width, output.height);

  return output;
}

PImage loadImageOrient(String filePath) {
  PImage im = loadImage(filePath);
  try {
    int orientation = getExifOrientation(filePath);
    switch (orientation) {
    case 3: // 180 degrees
      rotateImageInPlace(im, PI);
      break;
    case 6: // 90 degrees clockwise
      rotateImageInPlace(im, HALF_PI);
      break;
    case 8: // 90 degrees counterclockwise
      rotateImageInPlace(im, -HALF_PI);
      break;
    }
  }
  catch (Exception e) {
  }

  return im;
}

int getExifOrientation(String filePath) {
  // Read EXIF orientation
  try {
    Metadata metadata = ImageMetadataReader.readMetadata(new File(filePath));
    Directory directory = metadata.getFirstDirectoryOfType(ExifIFD0Directory.class);
    if (directory != null && directory.containsTag(ExifIFD0Directory.TAG_ORIENTATION)) {
      return directory.getInt(ExifIFD0Directory.TAG_ORIENTATION);
    }
  }
  catch (Exception e) {
    println("EXIF reading failed: " + e.getMessage());
  }
  return 1; // Default: no rotation
}

void rotateImageInPlace(PImage img, float angle) {
  // Rotate an image in place
  // Determine new dimensions after rotation
  int newWidth = (angle == HALF_PI || angle == -HALF_PI) ? img.height : img.width;
  int newHeight = (angle == HALF_PI || angle == -HALF_PI) ? img.width : img.height;

  // Create a new PGraphics canvas with correct dimensions
  PGraphics pg = createGraphics(newWidth, newHeight);
  pg.beginDraw();
  pg.translate(newWidth / 2, newHeight / 2); // Move origin to center
  pg.rotate(angle);

  // Adjust placement so the image is centered correctly
  if (angle == HALF_PI) {
    pg.image(img, -img.width / 2, -img.height / 2);
  } else if (angle == -HALF_PI) {
    pg.image(img, -img.width / 2, -img.height / 2);
  } else if (angle == PI) {
    pg.image(img, -img.width / 2, -img.height / 2);
  }

  pg.endDraw();

  // Update the original image with the rotated version
  img.resize(newWidth, newHeight);
  img.copy(pg.get(), 0, 0, newWidth, newHeight, 0, 0, newWidth, newHeight);
}

class CopyRectangle {
  PVector a;
  PVector size;
  PVector dirA;
  int strokeType = 0;
  int strokeLength = 0;
  PImage grabbed;
  float diag = 0;
  void draw() {
    if (isVisible()) {
      grabbed = get(round(a.x), round(a.y), round(size.x), round(size.y));
    }
    if (modulationSource==1) {
      if (random(1)<pow(audioSum, 2.0)) dirA = new PVector(random(1)<0.5?round(random(-3, 3)):0, random(1)<0.5?round(random(-3, 3)):0);
    } else if (modulationSource==2) {
      if (random(1)<pow(midiMod, 2.0)) dirA = new PVector(random(1)<0.5?round(random(-3, 3)):0, random(1)<0.5?round(random(-3, 3)):0);
    } else if (random(1)<0.01) {
      dirA = new PVector(random(1)<0.5?round(random(-3, 3)):0, random(1)<0.5?round(random(-3, 3)):0);
    }
    if (!freezeEffect) {
      if (modulationSource==1) a.add(PVector.mult(dirA, pow(audioSum, 0.5)*2.0));
      if (modulationSource==2) a.add(PVector.mult(dirA, pow(midiMod, 0.5)*2.0));
      else a.add(dirA);
      a.x = round(a.x);
      a.y = round(a.y);
      if (grabbed!=null) image(grabbed, a.x, a.y, size.x, size.y);
    }
  }
  boolean isVisible() {
    float margin = 130;
    return (a.x+size.x>=margin && a.x<=width-margin && a.y+size.y>=margin && a.y<=height-margin);
  }
}

void addNewCopyRectangle() {
  CopyRectangle r = new CopyRectangle();
  r.size = new PVector(round(random(50, 700)), round(random(50, 700)));
  r.a = new PVector(random(width-r.size.x), random(height-r.size.y));
  r.dirA = new PVector(random(1)<0.5?round(random(-3, 3)):0, random(1)<0.5?round(random(-3, 3)):0);
  r.strokeType = floor(random(2))+1;
  r.strokeLength = floor(random(2, random(2, 200)));
  r.diag = round(random(0, random(-20, 20)));
  copyRectangles.add(r);
}

PImage subCrop(PImage in, float scale) {
  PGraphics gr = createGraphics(in.width, in.height, JAVA2D);
  gr.beginDraw();
  gr.imageMode(CENTER);
  gr.image(in, (float)gr.width/2, (float)gr.height/2, (float)in.width*scale, (float)in.height*scale);
  gr.endDraw();
  return gr.get();
}

float[] averageBrightness(PImage background) {
  background.loadPixels();

  float sumR = 0, sumG = 0, sumB = 0;
  float minR = 0x100, minG = 0x100, minB = 0x100;
  float maxR = 0, maxG = 0, maxB = 0;
  int totalPixels = background.pixels.length;

  // Compute average color
  for (int i = 0; i < totalPixels; i+=50) {
    color c = background.pixels[i];
    sumR += red(c);
    sumG += green(c);
    sumB += blue(c);
    minR = min(minR, red(c));
    minG = min(minG, green(c));
    minB = min(minB, blue(c));
    maxR = max(maxR, red(c));
    maxG = max(maxG, green(c));
    maxB = max(maxB, blue(c));
  }

  float avgR = sumR / totalPixels;
  float avgG = sumG / totalPixels;
  float avgB = sumB / totalPixels;

  // Compute perceived brightness (luminance)
  float brightnessAvg = (0.299 * avgR + 0.587 * avgG + 0.114 * avgB); // Standard luminance formula
  float brightnessMin = (0.299 * minR + 0.587 * minG + 0.114 * minB); // Standard luminance formula
  float brightnessMax = (0.299 * maxR + 0.587 * maxG + 0.114 * maxB); // Standard luminance formula

  float[] brightness = new float[]{brightnessAvg, brightnessMin, brightnessMax};
  return brightness;
}

PVector getPossibleDynamicPoint(PImage im) {
  ArrayList<PVector> dP = getHighDynamicPoints(im, floor(random(1, 7)), floor(random(20, 100)));
  return dP.get(dP.size()-1);
}

ArrayList<PVector> getHighDynamicPoints(PImage img, int numPoints, int step) {
  img.loadPixels();
  int w = img.width;
  int h = img.height;

  float[][] contrastMap = new float[w / step][h / step];

  // Compute local contrast using a downsampled grid
  for (int x = step; x < w - step; x += step) {
    for (int y = step; y < h - step; y += step) {
      int index = y * w + x;

      // Sobel-like contrast estimation (on a downsampled grid)
      float gx = brightness(img.pixels[index - step + w]) - brightness(img.pixels[index + step + w]) +
        2 * (brightness(img.pixels[index - step]) - brightness(img.pixels[index + step])) +
        brightness(img.pixels[index - step - w]) - brightness(img.pixels[index + step - w]);

      float gy = brightness(img.pixels[index - w - step]) - brightness(img.pixels[index - w + step]) +
        2 * (brightness(img.pixels[index - w]) - brightness(img.pixels[index + w])) +
        brightness(img.pixels[index + w - step]) - brightness(img.pixels[index + w + step]);

      contrastMap[x / step][y / step] = sqrt(gx * gx + gy * gy); // Edge magnitude
    }
  }

  // Find the highest contrast points
  ArrayList<PVector> bestPoints = new ArrayList<PVector>();
  for (int i = 0; i < numPoints; i++) {
    float maxContrast = -1;
    int bestX = 0, bestY = 0;

    for (int x = 1; x < w / step - 1; x++) {
      for (int y = 1; y < h / step - 1; y++) {
        if (contrastMap[x][y] > maxContrast) {
          maxContrast = contrastMap[x][y];
          bestX = x * step;
          bestY = y * step;
        }
      }
    }

    // Store the best point found
    bestPoints.add(new PVector(bestX, bestY));

    // Suppress nearby values to avoid selecting the same region
    for (int dx = -2; dx <= 2; dx++) {
      for (int dy = -2; dy <= 2; dy++) {
        int nx = bestX / step + dx;
        int ny = bestY / step + dy;
        if (nx >= 0 && ny >= 0 && nx < w / step && ny < h / step) {
          contrastMap[nx][ny] = 0;
        }
      }
    }
  }

  return bestPoints;
}

color[] sortColorsByBrightness(color[] colors) {
  int n = colors.length;
  for (int i = 0; i < n - 1; i++) {
    int maxIndex = i;
    for (int j = i + 1; j < n; j++) {
      if (perceivedLuminance(colors[j]) > perceivedLuminance(colors[maxIndex])) {
        maxIndex = j;
      }
    }
    // Swap colors[i] with the brightest found
    color temp = colors[i];
    colors[i] = colors[maxIndex];
    colors[maxIndex] = temp;
  }
  return colors;
}

float perceivedLuminance(color c) {
  return 0.2126 * red(c) / 255 + 0.7152 * green(c) / 255 + 0.0722 * blue(c) / 255;
}

PImage convertImage(PImage img, int mode) {
  if (mode == 0) return img;

  PImage result = createImage(img.width, img.height, RGB);
  img.loadPixels();
  result.loadPixels();

  color[] gradient = {color(random(0, 0x80), random(0, 0x80), random(0, 0x80)),
    color(random(0x80, 0x100), random(0x80, 0x100), random(0x80, 0x100))};

  for (int i = 0; i < img.pixels.length; i++) {
    float luminance = perceivedLuminance(img.pixels[i]);
    result.pixels[i] = (mode == 1) ? color(luminance * 255) :
      (mode == 2) ? (luminance > 0.5 ? color(255) : color(0)) :
      mapToGradient(luminance, gradient);
  }

  result.updatePixels();
  return result;
}

color mapToGradient(float t, color[] g) {
  return lerpColor(g[0], g[1], t);
}

String[] getAllFilesFrom(String folderUrl) {
  File folder = new File(folderUrl);
  File[] filesPath = folder.listFiles();
  ArrayList<String> result = new ArrayList<String>();
  for (int i=0; i<filesPath.length; i++) {
    if (filesPath[i].isFile()) result.add(filesPath[i].toString());
  }
  return result.toArray(new String[result.size()]);
}

String[] getSubfolders(String baseFolder) {
  File folder = new File(baseFolder);
  File[] subFolders = folder.listFiles(File::isDirectory);
  ArrayList<String> result = new ArrayList<String>();

  for (File subFolder : subFolders) result.add(subFolder.getName());
  return result.toArray(new String[0]);
}

class MidiInputReceiver implements Receiver {
  public void send(MidiMessage message, long timeStamp) {
    byte[] data = message.getMessage();
    int status = data[0] & 0xF0;
    int channel = (data[0] & 0x0F) + 1;
    int data1 = data.length > 1 ? data[1] & 0x7F : 0;
    int data2 = data.length > 2 ? data[2] & 0x7F : 0;

    if (status == 0xB0) { // **Control Change (CC)**
      ccReceived(data1, data2, channel);
    } else if (status == 0x90 && data2 > 0) { // **Note On**
      noteReceived(data1, data2, channel);
    } else if (status == 0x80 || (status == 0x90 && data2 == 0)) { // **Note Off**
      noteReleased(data1, channel);
    }
  }

  public void close() {
  }
}

void ccReceived(int cc, int value, int channel) {
  println("CC: " + cc + " | Value: " + value + " | Channel: " + channel);
  if (cc==1) tempoMs = pow((float)value/127, 2)*10000;
  if (cc==2) midiMod = (float)value/127;
}

String midiInteraction ="";
void noteReceived(int note, int velocity, int channel) {
  println("Note ON: " + note + " | Velocity: " + velocity + " | Channel: " + channel);
  if (note==40) midiInteraction="black";
  if (note==41) midiInteraction="slideshows";
  if (note==42) midiInteraction="smear";
  if (note==43) midiInteraction="symmetries";
  if (note==36) midiInteraction="sorting";
  if (note==37) midiInteraction="modulationSource";
  if (note==38) midiInteraction="videoRec";
  if (note==39) midiInteraction="packs";
  if (note==44) midiInteraction="reload";
  if (note==45) midiInteraction="screenshot";
  if (note==46) midiInteraction="colorMode";
}

void noteReleased(int note, int channel) {
  println("Note OFF: " + note + " | Channel: " + channel);
}
