/**
 * OCCT C Wrapper Implementation
 * Provides C bindings for OpenCascade Technology (OCCT) 7.9.2
 *
 * Build command:
 *   clang++ -std=c++17 -shared -fPIC -o libocct_wrapper.dylib occt_c_wrapper.cpp \
 *     -I/opt/homebrew/include/opencascade \
 *     -L/opt/homebrew/lib \
 *     -lTKernel -lTKMath -lTKBRep -lTKG2d -lTKG3d -lTKGeomBase \
 *     -lTKGeomAlgo -lTKTopAlgo -lTKPrim -lTKBool -lTKFeat \
 *     -lTKMesh -lTKOffset -lTKFillet \
 *     -Wl,-rpath,/opt/homebrew/lib
 */

#include "occt_c_wrapper.h"

// OCCT Core Headers
#include <TopoDS.hxx>
#include <TopoDS_Shape.hxx>
#include <TopoDS_Wire.hxx>
#include <TopoDS_Face.hxx>
#include <TopoDS_Solid.hxx>
#include <TopoDS_Edge.hxx>
#include <TopoDS_Vertex.hxx>
#include <TopoDS_Compound.hxx>

// Geometry Headers
#include <gp_Pnt.hxx>
#include <gp_Vec.hxx>
#include <gp_Dir.hxx>
#include <gp_Ax1.hxx>
#include <gp_Ax2.hxx>

// B-Rep Building
#include <BRepBuilderAPI_MakeEdge.hxx>
#include <BRepBuilderAPI_MakeWire.hxx>
#include <BRepBuilderAPI_MakeFace.hxx>
#include <BRepBuilderAPI_MakeSolid.hxx>
#include <BRepBuilderAPI_Transform.hxx>

// Primitives and Features
#include <BRepPrimAPI_MakePrism.hxx>
#include <BRepPrimAPI_MakeRevol.hxx>
#include <BRepPrimAPI_MakeBox.hxx>
#include <BRepPrimAPI_MakeCylinder.hxx>
#include <BRepPrimAPI_MakeSphere.hxx>
#include <BRepPrimAPI_MakeCone.hxx>
#include <BRepPrimAPI_MakeTorus.hxx>

// Boolean Operations
#include <BRepAlgoAPI_Cut.hxx>
#include <BRepAlgoAPI_Fuse.hxx>
#include <BRepAlgoAPI_Common.hxx>

// Mesh Generation (Tessellation)
#include <BRepMesh_IncrementalMesh.hxx>
#include <Poly_Triangulation.hxx>
#include <TopExp_Explorer.hxx>
#include <TopLoc_Location.hxx>
#include <BRep_Tool.hxx>

// Utilities
#include <BRepCheck_Analyzer.hxx>
#include <Standard_Version.hxx>

#include <vector>
#include <cstring>
#include <cstdio>

// =============================================================================
// Internal Helpers - Convert between C and C++ types
// =============================================================================

static inline TopoDS_Shape* toShape(OCCT_Shape handle) {
    return reinterpret_cast<TopoDS_Shape*>(handle);
}

static inline OCCT_Shape fromShape(TopoDS_Shape* shape) {
    return reinterpret_cast<OCCT_Shape>(shape);
}

static inline gp_Pnt* toPnt(OCCT_Pnt handle) {
    return reinterpret_cast<gp_Pnt*>(handle);
}

static inline gp_Vec* toVec(OCCT_Vec handle) {
    return reinterpret_cast<gp_Vec*>(handle);
}

static inline gp_Dir* toDir(OCCT_Dir handle) {
    return reinterpret_cast<gp_Dir*>(handle);
}

static inline gp_Ax2* toAx2(OCCT_Ax2 handle) {
    return reinterpret_cast<gp_Ax2*>(handle);
}

// =============================================================================
// Memory Management
// =============================================================================

void OCCT_Shape_Delete(OCCT_Shape shape) {
    if (shape) {
        delete toShape(shape);
    }
}

bool OCCT_Shape_IsValid(OCCT_Shape shape) {
    if (!shape) return false;

    TopoDS_Shape* s = toShape(shape);
    if (s->IsNull()) return false;

    // Run topology validity check
    BRepCheck_Analyzer analyzer(*s);
    return analyzer.IsValid() ? true : false;
}

int OCCT_Shape_Type(OCCT_Shape shape) {
    if (!shape) return -1;

    TopoDS_Shape* s = toShape(shape);
    if (s->IsNull()) return -1;

    return static_cast<int>(s->ShapeType());
}

// =============================================================================
// Geometry Primitives (gp package)
// =============================================================================

OCCT_Pnt OCCT_Pnt_Create(double x, double y, double z) {
    gp_Pnt* pnt = new gp_Pnt(x, y, z);
    return reinterpret_cast<OCCT_Pnt>(pnt);
}

void OCCT_Pnt_Delete(OCCT_Pnt pnt) {
    if (pnt) {
        delete toPnt(pnt);
    }
}

OCCT_Vec OCCT_Vec_Create(double x, double y, double z) {
    gp_Vec* vec = new gp_Vec(x, y, z);
    return reinterpret_cast<OCCT_Vec>(vec);
}

void OCCT_Vec_Delete(OCCT_Vec vec) {
    if (vec) {
        delete toVec(vec);
    }
}

OCCT_Dir OCCT_Dir_Create(double x, double y, double z) {
    gp_Dir* dir = new gp_Dir(x, y, z);
    return reinterpret_cast<OCCT_Dir>(dir);
}

void OCCT_Dir_Delete(OCCT_Dir dir) {
    if (dir) {
        delete toDir(dir);
    }
}

OCCT_Ax2 OCCT_Ax2_Create(OCCT_Pnt origin, OCCT_Dir direction) {
    if (!origin || !direction) return nullptr;

    gp_Ax2* ax2 = new gp_Ax2(*toPnt(origin), *toDir(direction));
    return reinterpret_cast<OCCT_Ax2>(ax2);
}

void OCCT_Ax2_Delete(OCCT_Ax2 ax2) {
    if (ax2) {
        delete toAx2(ax2);
    }
}

// =============================================================================
// Wire Creation (2D Profile)
// =============================================================================

OCCT_Wire OCCT_Wire_FromPoints2D(const double* points, int num_points, bool closed) {
    if (!points || num_points < 2) return nullptr;

    try {
        BRepBuilderAPI_MakeWire wireBuilder;

        // Create edges connecting consecutive points on XY plane (Z=0)
        for (int i = 0; i < num_points; i++) {
            int next = (i + 1) % num_points;

            // Only connect to next if not at end (unless closed)
            if (i == num_points - 1 && !closed) break;

            gp_Pnt p1(points[i*2], points[i*2 + 1], 0.0);
            gp_Pnt p2(points[next*2], points[next*2 + 1], 0.0);

            // Skip degenerate edges (same point)
            if (p1.Distance(p2) < 1e-7) continue;

            BRepBuilderAPI_MakeEdge edgeBuilder(p1, p2);
            if (!edgeBuilder.IsDone()) continue;

            wireBuilder.Add(edgeBuilder.Edge());
        }

        if (!wireBuilder.IsDone()) return nullptr;

        TopoDS_Wire wire = wireBuilder.Wire();
        TopoDS_Shape* shape = new TopoDS_Shape(wire);
        return fromShape(shape);

    } catch (...) {
        return nullptr;
    }
}

OCCT_Wire OCCT_Wire_FromPoints3D(const double* points, int num_points, bool closed) {
    if (!points || num_points < 2) return nullptr;

    try {
        BRepBuilderAPI_MakeWire wireBuilder;

        // Create edges connecting consecutive points in 3D
        for (int i = 0; i < num_points; i++) {
            int next = (i + 1) % num_points;

            // Only connect to next if not at end (unless closed)
            if (i == num_points - 1 && !closed) break;

            gp_Pnt p1(points[i*3], points[i*3 + 1], points[i*3 + 2]);
            gp_Pnt p2(points[next*3], points[next*3 + 1], points[next*3 + 2]);

            // Skip degenerate edges
            if (p1.Distance(p2) < 1e-7) continue;

            BRepBuilderAPI_MakeEdge edgeBuilder(p1, p2);
            if (!edgeBuilder.IsDone()) continue;

            wireBuilder.Add(edgeBuilder.Edge());
        }

        if (!wireBuilder.IsDone()) return nullptr;

        TopoDS_Wire wire = wireBuilder.Wire();
        TopoDS_Shape* shape = new TopoDS_Shape(wire);
        return fromShape(shape);

    } catch (...) {
        return nullptr;
    }
}

void OCCT_Wire_Delete(OCCT_Wire wire) {
    OCCT_Shape_Delete(reinterpret_cast<OCCT_Shape>(wire));
}

// =============================================================================
// Extrusion (BRepPrimAPI_MakePrism)
// =============================================================================

OCCT_Shape OCCT_Extrude_Wire(OCCT_Wire wire, double vx, double vy, double vz) {
    if (!wire) return nullptr;

    try {
        TopoDS_Shape* wireShape = toShape(reinterpret_cast<OCCT_Shape>(wire));
        if (wireShape->IsNull()) return nullptr;

        TopoDS_Wire topoWire = TopoDS::Wire(*wireShape);

        // Create face from wire (required for solid extrusion)
        BRepBuilderAPI_MakeFace faceBuilder(topoWire, Standard_True);  // planar=true
        if (!faceBuilder.IsDone()) {
            std::cerr << "❌ OCCT: BRepBuilderAPI_MakeFace failed!" << std::endl;
            return nullptr;
        }

        TopoDS_Face face = faceBuilder.Face();

        // Extrude face along vector
        gp_Vec extrudeVec(vx, vy, vz);
        BRepPrimAPI_MakePrism prismBuilder(face, extrudeVec);
        if (!prismBuilder.IsDone()) {
            std::cerr << "❌ OCCT: BRepPrimAPI_MakePrism failed!" << std::endl;
            return nullptr;
        }

        TopoDS_Shape result = prismBuilder.Shape();

        // Debug: Check result type
        TopAbs_ShapeEnum resultType = result.ShapeType();
        std::cerr << "🔍 OCCT Extrude result type: " << resultType << std::endl;

        TopoDS_Shape* shape = new TopoDS_Shape(result);
        return fromShape(shape);

    } catch (Standard_Failure& e) {
        std::cerr << "❌ OCCT Exception in OCCT_Extrude_Wire: " << e.GetMessageString() << std::endl;
        return nullptr;
    } catch (...) {
        std::cerr << "❌ Unknown exception in OCCT_Extrude_Wire" << std::endl;
        return nullptr;
    }
}

OCCT_Shape OCCT_Extrude_Face(OCCT_Face face, double vx, double vy, double vz) {
    if (!face) return nullptr;

    try {
        TopoDS_Shape* faceShape = toShape(reinterpret_cast<OCCT_Shape>(face));
        if (faceShape->IsNull()) return nullptr;

        TopoDS_Face topoFace = TopoDS::Face(*faceShape);

        // Extrude face along vector
        gp_Vec extrudeVec(vx, vy, vz);
        BRepPrimAPI_MakePrism prismBuilder(topoFace, extrudeVec);
        if (!prismBuilder.IsDone()) return nullptr;

        TopoDS_Shape result = prismBuilder.Shape();
        TopoDS_Shape* shape = new TopoDS_Shape(result);
        return fromShape(shape);

    } catch (...) {
        return nullptr;
    }
}

// =============================================================================
// Revolution (BRepPrimAPI_MakeRevol)
// =============================================================================

OCCT_Shape OCCT_Revolve_Wire(OCCT_Wire wire, OCCT_Ax2 axis, double angle) {
    if (!wire || !axis) return nullptr;

    try {
        TopoDS_Shape* wireShape = toShape(reinterpret_cast<OCCT_Shape>(wire));
        if (wireShape->IsNull()) return nullptr;

        TopoDS_Wire topoWire = TopoDS::Wire(*wireShape);

        // Create face from wire
        BRepBuilderAPI_MakeFace faceBuilder(topoWire);
        if (!faceBuilder.IsDone()) return nullptr;

        TopoDS_Face face = faceBuilder.Face();

        // Convert gp_Ax2 to gp_Ax1 (axis of rotation)
        gp_Ax2* ax2 = toAx2(axis);
        gp_Ax1 ax1(ax2->Location(), ax2->Direction());

        // Revolve face around axis
        BRepPrimAPI_MakeRevol revolBuilder(face, ax1, angle);
        if (!revolBuilder.IsDone()) return nullptr;

        TopoDS_Shape result = revolBuilder.Shape();
        TopoDS_Shape* shape = new TopoDS_Shape(result);
        return fromShape(shape);

    } catch (...) {
        return nullptr;
    }
}

// =============================================================================
// Boolean Operations (BRepAlgoAPI)
// =============================================================================

OCCT_Shape OCCT_Boolean_Union(OCCT_Shape shape1, OCCT_Shape shape2) {
    if (!shape1 || !shape2) return nullptr;

    try {
        TopoDS_Shape* s1 = toShape(shape1);
        TopoDS_Shape* s2 = toShape(shape2);

        if (s1->IsNull() || s2->IsNull()) return nullptr;

        BRepAlgoAPI_Fuse fuseOp(*s1, *s2);
        if (!fuseOp.IsDone()) return nullptr;

        TopoDS_Shape result = fuseOp.Shape();
        TopoDS_Shape* shape = new TopoDS_Shape(result);
        return fromShape(shape);

    } catch (...) {
        return nullptr;
    }
}

OCCT_Shape OCCT_Boolean_Difference(OCCT_Shape base, OCCT_Shape tool) {
    if (!base || !tool) return nullptr;

    try {
        TopoDS_Shape* s1 = toShape(base);
        TopoDS_Shape* s2 = toShape(tool);

        if (s1->IsNull() || s2->IsNull()) return nullptr;

        BRepAlgoAPI_Cut cutOp(*s1, *s2);
        if (!cutOp.IsDone()) return nullptr;

        TopoDS_Shape result = cutOp.Shape();
        TopoDS_Shape* shape = new TopoDS_Shape(result);
        return fromShape(shape);

    } catch (...) {
        return nullptr;
    }
}

OCCT_Shape OCCT_Boolean_Intersection(OCCT_Shape shape1, OCCT_Shape shape2) {
    if (!shape1 || !shape2) return nullptr;

    try {
        TopoDS_Shape* s1 = toShape(shape1);
        TopoDS_Shape* s2 = toShape(shape2);

        if (s1->IsNull() || s2->IsNull()) return nullptr;

        BRepAlgoAPI_Common commonOp(*s1, *s2);
        if (!commonOp.IsDone()) return nullptr;

        TopoDS_Shape result = commonOp.Shape();
        TopoDS_Shape* shape = new TopoDS_Shape(result);
        return fromShape(shape);

    } catch (...) {
        return nullptr;
    }
}

// =============================================================================
// Primitive Shapes (BRepPrimAPI)
// =============================================================================

// Create box primitive (dimensions from origin)
OCCT_Shape OCCT_Primitive_Box(double dx, double dy, double dz) {
    printf("🔍 C++ DEBUG: OCCT_Primitive_Box(%.1f, %.1f, %.1f)\n", dx, dy, dz);

    if (dx <= 0 || dy <= 0 || dz <= 0) {
        printf("🔍 C++ DEBUG: ❌ Invalid dimensions (must be positive)\n");
        return nullptr;
    }

    try {
        printf("🔍 C++ DEBUG: Creating BRepPrimAPI_MakeBox...\n");
        BRepPrimAPI_MakeBox boxMaker(dx, dy, dz);

        printf("🔍 C++ DEBUG: Calling Build()...\n");
        boxMaker.Build();

        printf("🔍 C++ DEBUG: Checking if IsDone()...\n");
        if (!boxMaker.IsDone()) {
            printf("🔍 C++ DEBUG: ❌ boxMaker.IsDone() returned false after Build()\n");
            return nullptr;
        }

        printf("🔍 C++ DEBUG: Getting shape...\n");
        TopoDS_Shape box = boxMaker.Shape();

        printf("🔍 C++ DEBUG: Creating new TopoDS_Shape...\n");
        TopoDS_Shape* result = new TopoDS_Shape(box);

        printf("🔍 C++ DEBUG: ✓ Box created successfully, returning %p\n", result);
        return fromShape(result);

    } catch (const std::exception& e) {
        printf("🔍 C++ DEBUG: ❌ Exception caught: %s\n", e.what());
        return nullptr;
    } catch (...) {
        printf("🔍 C++ DEBUG: ❌ Unknown exception caught\n");
        return nullptr;
    }
}

// Create box primitive between two corner points
OCCT_Shape OCCT_Primitive_Box_TwoCorners(double x1, double y1, double z1,
                                          double x2, double y2, double z2) {
    try {
        gp_Pnt p1(x1, y1, z1);
        gp_Pnt p2(x2, y2, z2);

        BRepPrimAPI_MakeBox boxMaker(p1, p2);
        if (!boxMaker.IsDone()) return nullptr;

        TopoDS_Shape box = boxMaker.Shape();
        return fromShape(new TopoDS_Shape(box));

    } catch (...) {
        return nullptr;
    }
}

// Create cylinder primitive (centered at origin, along Z axis)
OCCT_Shape OCCT_Primitive_Cylinder(double radius, double height) {
    if (radius <= 0 || height <= 0) return nullptr;

    try {
        BRepPrimAPI_MakeCylinder cylMaker(radius, height);
        cylMaker.Build();  // Explicit build call
        if (!cylMaker.IsDone()) return nullptr;

        TopoDS_Shape cylinder = cylMaker.Shape();
        return fromShape(new TopoDS_Shape(cylinder));

    } catch (...) {
        return nullptr;
    }
}

// Create cylinder with custom axis
OCCT_Shape OCCT_Primitive_Cylinder_Axis(OCCT_Pnt base, OCCT_Dir axis,
                                         double radius, double height) {
    if (!base || !axis || radius <= 0 || height <= 0) return nullptr;

    try {
        gp_Ax2 ax(*toPnt(base), *toDir(axis));

        BRepPrimAPI_MakeCylinder cylMaker(ax, radius, height);
        if (!cylMaker.IsDone()) return nullptr;

        TopoDS_Shape cylinder = cylMaker.Shape();
        return fromShape(new TopoDS_Shape(cylinder));

    } catch (...) {
        return nullptr;
    }
}

// Create sphere primitive (centered at origin)
OCCT_Shape OCCT_Primitive_Sphere(double radius) {
    if (radius <= 0) return nullptr;

    try {
        BRepPrimAPI_MakeSphere sphereMaker(radius);
        sphereMaker.Build();  // Explicit build call
        if (!sphereMaker.IsDone()) return nullptr;

        TopoDS_Shape sphere = sphereMaker.Shape();
        return fromShape(new TopoDS_Shape(sphere));

    } catch (...) {
        return nullptr;
    }
}

// Create sphere at specific center point
OCCT_Shape OCCT_Primitive_Sphere_Center(OCCT_Pnt center, double radius) {
    if (!center || radius <= 0) return nullptr;

    try {
        BRepPrimAPI_MakeSphere sphereMaker(*toPnt(center), radius);
        if (!sphereMaker.IsDone()) return nullptr;

        TopoDS_Shape sphere = sphereMaker.Shape();
        return fromShape(new TopoDS_Shape(sphere));

    } catch (...) {
        return nullptr;
    }
}

// Create cone primitive (centered at origin, along Z axis)
OCCT_Shape OCCT_Primitive_Cone(double radius1, double radius2, double height) {
    if (radius1 < 0 || radius2 < 0 || height <= 0) return nullptr;
    if (radius1 == 0 && radius2 == 0) return nullptr;  // Both radii can't be zero

    try {
        BRepPrimAPI_MakeCone coneMaker(radius1, radius2, height);
        coneMaker.Build();  // Explicit build call
        if (!coneMaker.IsDone()) return nullptr;

        TopoDS_Shape cone = coneMaker.Shape();
        return fromShape(new TopoDS_Shape(cone));

    } catch (...) {
        return nullptr;
    }
}

// Create torus primitive (centered at origin, in XY plane)
OCCT_Shape OCCT_Primitive_Torus(double major_radius, double minor_radius) {
    if (major_radius <= 0 || minor_radius <= 0) return nullptr;
    if (minor_radius >= major_radius) return nullptr;  // Minor must be less than major

    try {
        BRepPrimAPI_MakeTorus torusMaker(major_radius, minor_radius);
        torusMaker.Build();  // Explicit build call
        if (!torusMaker.IsDone()) return nullptr;

        TopoDS_Shape torus = torusMaker.Shape();
        return fromShape(new TopoDS_Shape(torus));

    } catch (...) {
        return nullptr;
    }
}

// =============================================================================
// Tessellation (Mesh Generation for Rendering)
// =============================================================================

OCCT_Mesh* OCCT_Tessellate(OCCT_Shape shape, OCCT_TessellationParams params) {
    if (!shape) return nullptr;

    try {
        TopoDS_Shape* topoShape = toShape(shape);
        if (topoShape->IsNull()) return nullptr;

        // Generate mesh with specified parameters
        BRepMesh_IncrementalMesh mesher(
            *topoShape,
            params.linear_deflection,
            params.relative,
            params.angular_deflection
        );

        if (!mesher.IsDone()) return nullptr;

        // Collect all triangles from all faces
        std::vector<float> vertices;
        std::vector<float> normals;
        std::vector<int> triangles;

        // Explore all faces in the shape
        for (TopExp_Explorer exp(*topoShape, TopAbs_FACE); exp.More(); exp.Next()) {
            TopoDS_Face face = TopoDS::Face(exp.Current());
            TopLoc_Location location;

            // Get triangulation
            const Handle(Poly_Triangulation)& tri = BRep_Tool::Triangulation(face, location);
            if (tri.IsNull()) continue;

            // Get transformation
            gp_Trsf transform = location.Transformation();

            int vertex_offset = vertices.size() / 3;

            // Store original nodes for normal calculation
            std::vector<gp_Pnt> nodes;
            nodes.reserve(tri->NbNodes());

            // Add vertices (transformed)
            for (int i = 1; i <= tri->NbNodes(); i++) {
                gp_Pnt p = tri->Node(i).Transformed(transform);
                nodes.push_back(p);
                vertices.push_back(static_cast<float>(p.X()));
                vertices.push_back(static_cast<float>(p.Y()));
                vertices.push_back(static_cast<float>(p.Z()));
            }

            // Initialize normals (will be computed per-triangle and averaged)
            std::vector<gp_Vec> nodeNormals(tri->NbNodes(), gp_Vec(0, 0, 0));

            // Calculate normal for each triangle and accumulate at vertices
            for (int i = 1; i <= tri->NbTriangles(); i++) {
                const Poly_Triangle& t = tri->Triangle(i);
                int n1, n2, n3;
                t.Get(n1, n2, n3);

                // Get triangle vertices (OCCT uses 1-based indexing)
                const gp_Pnt& p1 = nodes[n1 - 1];
                const gp_Pnt& p2 = nodes[n2 - 1];
                const gp_Pnt& p3 = nodes[n3 - 1];

                // Calculate triangle normal (cross product)
                gp_Vec v1(p1, p2);
                gp_Vec v2(p1, p3);
                gp_Vec triNormal = v1.Crossed(v2);

                // Accumulate normal at each vertex
                nodeNormals[n1 - 1] += triNormal;
                nodeNormals[n2 - 1] += triNormal;
                nodeNormals[n3 - 1] += triNormal;
            }

            // Normalize and store vertex normals
            for (size_t i = 0; i < nodeNormals.size(); i++) {
                gp_Vec& n = nodeNormals[i];
                if (n.Magnitude() > 1e-7) {
                    n.Normalize();
                }
                normals.push_back(static_cast<float>(n.X()));
                normals.push_back(static_cast<float>(n.Y()));
                normals.push_back(static_cast<float>(n.Z()));
            }

            // Add triangles (offset by current vertex count)
            for (int i = 1; i <= tri->NbTriangles(); i++) {
                const Poly_Triangle& t = tri->Triangle(i);
                int n1, n2, n3;
                t.Get(n1, n2, n3);

                // Convert to 0-based indexing and add offset
                triangles.push_back(vertex_offset + n1 - 1);
                triangles.push_back(vertex_offset + n2 - 1);
                triangles.push_back(vertex_offset + n3 - 1);
            }
        }

        if (vertices.empty() || triangles.empty()) return nullptr;

        // Allocate mesh structure
        OCCT_Mesh* mesh = new OCCT_Mesh();
        mesh->num_vertices = vertices.size() / 3;
        mesh->num_triangles = triangles.size() / 3;

        // Allocate and copy vertex data
        mesh->vertices = new float[vertices.size()];
        std::memcpy(mesh->vertices, vertices.data(), vertices.size() * sizeof(float));

        // Allocate and copy normal data
        mesh->normals = new float[normals.size()];
        std::memcpy(mesh->normals, normals.data(), normals.size() * sizeof(float));

        // Allocate and copy triangle indices
        mesh->triangles = new int[triangles.size()];
        std::memcpy(mesh->triangles, triangles.data(), triangles.size() * sizeof(int));

        return mesh;

    } catch (...) {
        return nullptr;
    }
}

void OCCT_Mesh_Delete(OCCT_Mesh* mesh) {
    if (mesh) {
        delete[] mesh->vertices;
        delete[] mesh->normals;
        delete[] mesh->triangles;
        delete mesh;
    }
}

// =============================================================================
// Utility Functions
// =============================================================================

const char* OCCT_Version() {
    return OCC_VERSION_STRING_EXT;
}

void OCCT_Initialize() {
    // OCCT initialization (if needed)
    // Currently nothing required
}

void OCCT_Cleanup() {
    // OCCT cleanup (if needed)
    // Currently nothing required
}
