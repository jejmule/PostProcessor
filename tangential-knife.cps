/**
  Copyright (C) 2012-2013 by Autodesk, Inc.
  All rights reserved.

  Generic 2D post processor configuration.

  $Revision: 42473 905303e8374380273c82d214b32b7e80091ba92e $
  $Date: 2019-09-04 07:46:02 $
  
  FORKID {F2FA3EAF-E822-4778-A478-1370D795992E}
*/

description = "Generic 2D";
vendor = "Autodesk";
vendorUrl = "http://www.autodesk.com";
legal = "Copyright (C) 2012-2013 by Autodesk, Inc.";
certificationLevel = 2;

longDescription = "Generic ISO milling post for 2D.";

extension = "nc";
setCodePage("ascii");

capabilities = CAPABILITY_JET;
tolerance = spatial(0.002, MM);
minimumChordLength = spatial(0.25, MM);
minimumCircularRadius = spatial(0.01, MM);
maximumCircularRadius = spatial(1000, MM);
minimumCircularSweep = toRad(0.01);
maximumCircularSweep = toRad(180);
allowHelicalMoves = true;
//allowedCircularPlanes = PLANE_XY;
allowedCircularPlanes = undefined;

// user-defined properties
properties = {
  useFeed: true // enable to use F output
};

// user-defined property definitions
propertyDefinitions = {
  useFeed: {title:"Use feed", description:"Enable to use F output.", type:"boolean"}
};

var WARNING_WORK_OFFSET = 0;
var WARNING_COOLANT = 1;

var gFormat = createFormat({prefix:"G", decimals:0, width:2, zeropad:true});
var mFormat = createFormat({prefix:"M", decimals:0});

var xyzFormat = createFormat({decimals:(unit == MM ? 3 : 4)});
var abcFormat = createFormat({decimals:3, forceDecimal:true, scale:DEG});
var feedFormat = createFormat({decimals:(unit == MM ? 2 : 3)});

var xOutput = createVariable({prefix:"X"}, xyzFormat);
var yOutput = createVariable({prefix:"Y"}, xyzFormat);
var cOutput = createVariable({prefix:"C"}, abcFormat);
var iOutput = createReferenceVariable({prefix:"I"}, xyzFormat);
var jOutput = createReferenceVariable({prefix:"J"}, xyzFormat);
var feedOutput = createVariable({prefix:"F"}, feedFormat);

var gMotionModal = createModal({}, gFormat); // modal group 1 // G0-G3, ...
var gAbsIncModal = createModal({}, gFormat); // modal group 3 // G90-91
var mOutput = createModal({},mFormat); // modal group for M codes

var sequenceNumber = 0;

//specific section for tangential knife
var c_rad = 0;  // Current C axis position
var liftAtCorner_rad = toRad(5);       // dont'lift the knife is angle shift is less than liftAtCorner
var up = false;   //is the knife up?

/**
 Update C position for tangenmtial knife
 */
 function updateC(target_rad) {
  //check if we should rotate the head
  var delta_rad = (target_rad-c_rad) % (2*Math.PI)
  if (Math.abs(delta_rad) > liftAtCorner_rad) {
    moveUp()
    gMotionModal.reset()
    writeBlock(gMotionModal.format(0), cOutput.format(target_rad));
    moveDown()
  }
  else if (delta_rad == 0){
  }
  else {
    writeBlock(gMotionModal.format(1), cOutput.format(target_rad));
  }
  c_rad = target_rad
  return;
 }

 function moveUp() {
   writeComment('lift up');
   writeComment(String.concat('tool ',tool.number));
   //M55 P1-9 clear aux 1-9
   mFormat.format(55)
   return;
 }

 function moveDown() {
  writeComment('lift down');
  return;
 }

/**
  Writes the specified block.
*/
function writeBlock() {
  writeWords2("N" + sequenceNumber, arguments);
  sequenceNumber += 1;
}

/**
  Output a comment.
*/
function writeComment(text) {
  writeln("(" + text + ")");
}

function onOpen() {
  if (!properties.useFeed) {
    feedOutput.disable();
  }
  
  if (programName) {
    writeComment(programName);
  }
  if (programComment) {
    writeComment(programComment);
  }

  writeBlock(gAbsIncModal.format(90));

  var cAxis = createAxis({coordinate:Z, table:false, axis:[0, 0, 1], cyclic:true}); 
  machineConfiguration = new MachineConfiguration(cAxis);
  setMachineConfiguration(machineConfiguration);
}

function onComment(message) {
  writeComment(message);
}

function onSection() {

  if (!isSameDirection(currentSection.workPlane.forward, new Vector(0, 0, 1))) {
    error(localize("Tool orientation is not supported."));
    return;
  }
  setRotation(currentSection.workPlane);

  if (currentSection.workOffset != 0) {
    warningOnce(localize("Work offset is not supported."), WARNING_WORK_OFFSET);
  }
  if (tool.coolant != COOLANT_OFF) {
    warningOnce(localize("Coolant not supported."), WARNING_COOLANT);
  }
  //select the right spindle
  //on my machine there are 4 pindle, selected by M90-91-92-93-94 G code
  var command;
  switch(tool.number) {
    case(1):
      command = 91;
      break;
    case(2):
      command = 92;
      break;
    case(3):
      command = 95;
      break;1
    case (4):
      command = 97;
      break;
    default :
      command = 90;
      break
  }
  writeComment('Select spindle #'+tool.number)
  writeBlock(mFormat.format(command))
  feedOutput.reset();
}

function onPower(power) {
  if(power) {
    writeBlock(mFormat.format(2)); //M2 switch on spindle, in this case move knife down
  }
  else {
    writeBlock(mFormat.format(5)); //M5 siwtch off spindle, move up
  }
}

function onRapid(_x, _y, _z) {
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);

  if (x || y) {
    writeBlock(gMotionModal.format(0), x, y);
    feedOutput.reset();
  }

  var start = getCurrentPosition();
  var delta = start.z-_z;
  if ( delta <0) { //Head is down
    moveUp();
  
  }
  //ther is no need to move down the head this is manaaged by updateC when we know the direction
}

function onLinear(_x, _y, _z, feed) {
  var start = getCurrentPosition();
  var target = new Vector(_x,_y,_z);
  var direction = Vector.diff(target,start);
  //compute orientation of the upcoming segment
  var orientation_rad = direction.getXYAngle();
  updateC(orientation_rad);
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);; 
  if (x || y) {
    writeBlock(gMotionModal.format(1), x, y, feedOutput.format(feed));
  }
}

function onCircular(clockwise, cx, cy, cz, x, y, z, feed) {
  if (isHelical()) {
    var t = tolerance;
    if (hasParameter("operation:tolerance")) {
      t = getParameter("operation:tolerance");
    }
    linearize(t);
    return;
  }

  // one of X/Y and I/J are required and likewise


  switch (getCircularPlane()) {
  case PLANE_XY:
    var start = getCurrentPosition();
    var center = new Vector(cx,cy,cz);
    var start_center = Vector.diff(start,center);
    var up = new Vector(0,0,1);
    var start_dir = Vector.cross(start_center,up);
    var start_angle = start_dir.getXYAngle();
    var end = new Vector(x,y,z);
    var end_center = Vector.diff(end,center);
    var end_dir = Vector.cross(end_center,up);
    var end_angle = end_dir.getXYAngle();
    updateC(start_angle);
    c_rad = end_angle;
    writeBlock(gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), cOutput.format(end_angle), iOutput.format(cx - start.x, 0), jOutput.format(cy - start.y, 0), feedOutput.format(feed));
    break;
  default:
    var t = tolerance;
    if (hasParameter("operation:tolerance")) {
      t = getParameter("operation:tolerance");
    }
    linearize(t);
  }
}
/*
function onSectionEnd() {
  //move the head up
  moveUp();
}*/

function onCommand(command) {
}

function onClose() {
  writeComment('select spindle 0');
  writeBlock(mOutput.format(90)); //Set back spindle 0
  writeComment('go to corner')
  writeBlock(gMotionModal.format(30)) //Move to parking position 2
}
