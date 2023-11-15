#include <jetson-utils/videoSource.h>
#include <jetson-utils/videoOutput.h>

__global__ void rgb2grayKernel(uchar4 *image, uchar4 *outputImage, int width, int height)
{

    int total = width * height;
    int index = threadIdx.x + blockIdx.x * blockDim.x;
    int stride = blockDim.x * gridDim.x;
    for (size_t i = index; i < total; i += stride)
    {

        unsigned char gray = image[i].x * 0.299 + image[i].y * 0.587 + image[i].z * 0.114;
        outputImage[i].x = gray;
        outputImage[i].y = gray;
        outputImage[i].z = gray;
    }
}

int main(int argc, char **argv)
{
    // create input/output streams
    videoSource *input = videoSource::Create(argc, argv, ARG_POSITION(0));
    videoOutput *output = videoOutput::Create(argc, argv, ARG_POSITION(1));
    videoOutput *output2 = videoOutput::Create(argc, argv, ARG_POSITION(1));
    uchar4 *outputImage = NULL;
    cudaMalloc(&outputImage, sizeof(uchar4) * 720 * 1280);
    if (!input)
        return 0;

    // capture/display loop
    while (true)
    {

        uchar4 *image = NULL;
        //  can be uchar3, uchar4, float3, float4
        int status = 0;                             // see videoSource::Status (OK, TIMEOUT, EOS, ERROR)
        if (!input->Capture(&image, 1000, &status)) // 1000ms timeout (default)
        {
            if (status == videoSource::TIMEOUT)
                continue;
            break; // EOS
        }
        rgb2grayKernel<<<16, 1024>>>(image, outputImage, input->GetWidth(), input->GetHeight());
        if (output != NULL)
        {

            output->Render(image, input->GetWidth(), input->GetHeight());

            // Update status bar
            char str[256];
            sprintf(str, "Camera Viewer (%ux%u) | %0.1f FPS", input->GetWidth(),
                    input->GetHeight(), output->GetFrameRate());
            output->SetStatus(str);

            if (!output->IsStreaming()) // check if the user quit
                break;
        }
        if (output2 != NULL)
        {

            output2->Render(outputImage, input->GetWidth(), input->GetHeight());
            // Update status bar
            char str[256];
            sprintf(str, "Camera Viewer (%ux%u) | %0.1f FPS", input->GetWidth(),
                    input->GetHeight(), output2->GetFrameRate());

            output2->SetStatus(str);
            if (!output2->IsStreaming()) // check if the user quit
                break;
        }
    }
    cudaFree(outputImage);
}