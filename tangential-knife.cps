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
allowedCircularPlanes = PLANE_XY;

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
var liftAtCorner_rad = toRad(1.8);       // dont'lift the knife is angle shift is less than liftAtCorner

/**
 Update C position for tangenmtial knife
 */

 function updateC(target_rad) {
  //check if we should rotate the head
  var delta_rad = Math.abs(target_rad-c_rad)
  if (Math.abs(delta_rad) > liftAtCorner_rad) {
    moveUp()
    writeBlock(gMotionModal.format(0), cOutput.format(target_rad));
    moveDown()
  }
  else {
    writeBlock(gMotionModal.format(1), cOutput.format(target_rad));
  }
  c_rad = target_rad
  return;
 }

 function moveUp() {
   writeComment('lift up');
   writeComment(tool.number);
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
  
  feedOutput.reset();
}

function onRapid(_x, _y, _z) {
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  if (x || y) {
    writeBlock(gMotionModal.format(0), x, y);
    feedOutput.reset();
  }
}

function onLinear(_x, _y, _z, feed) {
  var start = getCurrentPosition();
  //compute orientation of the upcoming segment
  var c_target_rad = Math.atan((_y-start.y)/(_x-start.x));
  updateC(c_target_rad);
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

  var start = getCurrentPosition();
  switch (getCircularPlane()) {
  case PLANE_XY:
    writeBlock(gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), iOutput.format(cx - start.x, 0), jOutput.format(cy - start.y, 0), feedOutput.format(feed));
    break;
  default:
    var t = tolerance;
    if (hasParameter("operation:tolerance")) {
      t = getParameter("operation:tolerance");
    }
    linearize(t);
  }
}

function onCommand(command) {
}

function onClose() {
  writeComment('spindle 0 : laser spot')
  writeBlock(mOutput.format(90)); //Set back spindle 0 (laser spot)
  writeComment('go to corner')
  writeBlock(gMotionModal.format(30)) //Move to parking position 2 (corner)
}
