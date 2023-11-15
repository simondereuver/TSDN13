#include <jetson-utils/videoSource.h>
#include <jetson-utils/videoOutput.h>

__global__ void plotHistogramKernel(uchar4 *image, int *histogram, int width, int height, int max_freq)
{
    int index = blockIdx.x * blockDim.x + threadIdx.x;
    uchar4 white_pixel = make_uchar4(255, 255, 255, 255);
    // uchar4 black_pixel = make_uchar4(0, 0, 0, 255);
    if (index < 256)
    {
        int freq = histogram[index] * 256 / max_freq;
        for (int i = 0; i < 256; i++)
        {
            int row = height - i - 1;
            if (i <= freq)
            {
                image[row * width + 2 * index] = white_pixel;
                image[row * width + 2 * index + 1] = white_pixel;
            }
            else
            {
                uchar4 transparent_pixel = make_uchar4(image[row * width + 2 * index].x * 0.7, image[row * width + 2 * index].y * 0.7,
                                                       image[row * width + 2 * index].z * 0.7, image[row * width + 2 * index].w * 0.7);
                uchar4 transparent_pixel_plus_one = make_uchar4(image[row * width + 2 * index + 1].x * 0.7, image[row * width + 2 * index + 1].y * 0.7,
                                                                image[row * width + 2 * index + 1].z * 0.7, image[row * width + 2 * index + 1].w * 0.7);
                image[row * width + 2 * index] = transparent_pixel;
                image[row * width + 2 * index + 1] = transparent_pixel_plus_one;
            }
        }
    }
}

__global__ void rgb2grayKernel(uchar4 *image, uchar4 *outputImage, int height, int width)
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

__global__ void calcHistogramKernel(uchar4 *image, int *histogram, int height, int width)
{
    int total = width * height;
    int index = threadIdx.x + blockIdx.x * blockDim.x;
    int stride = blockDim.x * gridDim.x;
    int rgbValue;

    __shared__ int histo_local[256];

    if (threadIdx.x < 256)
    {
        histo_local[threadIdx.x] = 0;
    }
    __syncthreads();

    for (size_t i = index; i < total; i += stride)
    {

        rgbValue = image[i].x;
        atomicAdd(&histo_local[rgbValue], 1);
    }
    __syncthreads();
    if (threadIdx.x < 256)
    {
        atomicAdd(&histogram[threadIdx.x], histo_local[threadIdx.x]);
    }
}

int main(int argc, char **argv)
{
    // create input/output streams
    videoSource *input = videoSource::Create(argc, argv, ARG_POSITION(0));
    videoOutput *output = videoOutput::Create(argc, argv, ARG_POSITION(1));

    uchar4 *outputImage = NULL;

    cudaMalloc(&outputImage, sizeof(uchar4) * 720 * 1280);

    int hostHistogram[256] = {0};

    int *deviceHistogram = NULL;

    cudaMalloc(&deviceHistogram, sizeof(int) * 256);

    if (!input)
        return 0;

    // capture/display loop
    while (true)
    {
        int totalPixels = 0;
        uchar4 *image = NULL;

        //  can be uchar3, uchar4, float3, float4
        int status = 0;                             // see videoSource::Status (OK, TIMEOUT, EOS, ERROR)
        if (!input->Capture(&image, 1000, &status)) // 1000ms timeout (default)
        {
            if (status == videoSource::TIMEOUT)
                continue;
            break; // EOS
        }

        if (output != NULL)
        {
            memset(hostHistogram, 0, sizeof(int) * 256);
            cudaMemcpy(deviceHistogram, hostHistogram, 256 * sizeof(int), cudaMemcpyHostToDevice);
            rgb2grayKernel<<<16, 1024>>>(image, outputImage, input->GetHeight(), input->GetWidth());
            calcHistogramKernel<<<16, 1024>>>(outputImage, deviceHistogram, input->GetHeight(), input->GetWidth());
            cudaMemcpy(hostHistogram, deviceHistogram, 256 * sizeof(int), cudaMemcpyDeviceToHost);
            plotHistogramKernel<<<256, 1>>>(outputImage, deviceHistogram, input->GetWidth(), input->GetHeight(), 20000);
            output->Render(outputImage, input->GetWidth(), input->GetHeight());
            // Update status bar
            char str[256];
            sprintf(str, "Camera Viewer (%ux%u) | %0.1f FPS", input->GetWidth(),
                    input->GetHeight(), output->GetFrameRate());

            output->SetStatus(str);
            if (!output->IsStreaming()) // check if the user quit
                break;
            for (int i = 0; i < 256; i++)
            {
                totalPixels += hostHistogram[i];
            }
            printf("%d\n", totalPixels);
        }
    }
    cudaFree(outputImage);
    cudaFree(deviceHistogram);
}