#ifndef KV_MAPPER_EVAL_H
#define KV_MAPPER_EVAL_H

#include "Values.h"
#include "core/SingleInputTransformEvaluator.h"

#include "streambench/Mapper/TemporalKVMapper.h"

template <typename InputT, typename OutputT, template<class> class BundleT>
	class TemporalKVMapperEvaluator : 
		public SingleInputTransformEvaluator<
	   		TemporalKVMapper<InputT, OutputT, BundleT>, BundleT<InputT>, BundleT<OutputT>
		>
{
	using InputBundleT = BundleT<InputT>;
	using OutputBundleT = BundleT<OutputT>;
	using TransformT = TemporalKVMapper<InputT, OutputT, BundleT>;

public:
	bool evaluateSingleInput (TransformT* trans, shared_ptr<InputBundleT> input_bundle,
			shared_ptr<OutputBundleT> output_bundle) override
	{
		for (auto && it = input_bundle->begin(); it != input_bundle->end(); ++it) {
			trans->do_map(*it, output_bundle);
		}
		return true;
	}

	TemporalKVMapperEvaluator(int node) :
		SingleInputTransformEvaluator<TransformT, InputBundleT, OutputBundleT>(node)
	{}
};

#endif // KV_MAPPER_EVAL_H
