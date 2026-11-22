// Shadery Metal (SceneKit shader modifiers) gry Bilard.
// Każda sekcja zaczyna się od linii "// ==== nazwa" i jest wczytywana w czasie działania przez TableBuilder.
// Są to fragmenty w języku Metal Shading Language wstrzykiwane do potoku PBR SceneKit (renderowanego przez Metal).

// ==== cloth_surface
#pragma arguments
float topMix;
#pragma body
// Włosy sukna: jaśniejsza, „aksamitna” krawędź pod małym kątem patrzenia + delikatne sploty
float3 N = normalize(_surface.normal);
float3 V = normalize(_surface.view);
float rim = pow(saturate(1.0 - dot(N, V)), 2.2);
_surface.diffuse.rgb *= 1.0 + 0.22 * rim;
_surface.diffuse.rgb += _surface.diffuse.rgb * 0.08 * rim;
_surface.roughness = mix(clamp(_surface.roughness, 0.80, 1.0), 0.92, topMix);   // z góry stała chropowatość: brak migotania blasku
_surface.metalness = 0.0;

// ==== ball_surface
#pragma arguments
float3 lampDirV;
#pragma body
// Dwuwarstwowy model odbić: (1) zewnętrzny lakier – ostre odbicie lampy (clearcoat SceneKit, GGX),
// (2) pigment pod spodem – szerszy, miękki lob rozproszonego połysku w kolorze bili, plus Fresnel.
float3 N = normalize(_surface.normal);
float3 V = normalize(_surface.view);
float3 Lh = normalize(normalize(lampDirV) + V);
float soft = pow(saturate(dot(N, Lh)), 26.0);
float fres = pow(saturate(1.0 - dot(N, V)), 4.0);
_surface.specular.rgb += _surface.diffuse.rgb * (0.30 * soft) + float3(0.10) * fres;
_surface.diffuse.rgb *= 1.0 + 0.08 * soft;

// ==== ball_pearl
#pragma arguments
float3 lampDirV;
#pragma body
// Dwuwarstwowy model odbić: (1) zewnętrzny lakier – ostre odbicie lampy (clearcoat SceneKit, GGX),
// (2) pigment pod spodem – szerszy, miękki lob rozproszonego połysku w kolorze bili, plus Fresnel.
float3 N = normalize(_surface.normal);
float3 V = normalize(_surface.view);
float3 Lh = normalize(normalize(lampDirV) + V);
float soft = pow(saturate(dot(N, Lh)), 26.0);
float fres = pow(saturate(1.0 - dot(N, V)), 4.0);
_surface.specular.rgb += _surface.diffuse.rgb * (0.30 * soft) + float3(0.10) * fres;
_surface.diffuse.rgb *= 1.0 + 0.08 * soft;
// zestaw perłowy: cienka warstwa (iryzacja) – barwa przesuwa się z kątem patrzenia, mocniej ku krawędzi
float t = 1.0 - saturate(dot(N, V));
float3 film = 0.5 + 0.5 * cos(6.2832 * (float3(0.0, 0.33, 0.67) + t * 1.4 + N.y * 0.25));
_surface.diffuse.rgb = mix(_surface.diffuse.rgb, _surface.diffuse.rgb * (0.7 + 0.6 * film), 0.25 + 0.6 * t);
_surface.specular.rgb += film * (0.06 + 0.25 * t * t);

// ==== wood_surface
#pragma body
// Satynowy połysk lakierowanego mahoniu
float3 N = normalize(_surface.normal);
float3 V = normalize(_surface.view);
float fres = pow(saturate(1.0 - dot(N, V)), 3.0);
_surface.specular.rgb += float3(0.18) * fres;
